import Foundation
import Phrasing
import SessionHealthCore

/// The one decision about notifications that is the person's: say something, or keep quiet.
///
/// Two things are worth holding here, and they are different in kind. One is the record itself
/// — a choice that did not survive a restart or an update would be the app quietly overruling
/// somebody every time they dragged a new copy over the old one. The other is where the silence
/// is allowed to live: at the very edge, after everything upstream has done its accounting, so
/// that switching the notifications back on does not empty a backlog onto whoever just asked to
/// be interrupted again.
func runNotificationChoiceTests(_ suite: TestSuite, config: ThresholdConfig) {
    // MARK: The record

    withTemporaryDirectory(suite, named: "notification-choice") { directory in
        let url = NotificationChoice.url(in: directory)

        suite.test("an app nobody has told to be quiet speaks, and leaves nothing on the disk") {
            suite.expect(!NotificationChoice.isSilenced(at: url), "silent with no choice made")
            suite.expect(
                !FileManager.default.fileExists(atPath: url.path),
                "a person who never opened the window must leave no file behind"
            )
        }

        // A restart is nothing but this: the answer comes off the disk rather than out of a
        // process that has since ended.
        suite.test("silence comes back the way it was chosen") {
            suite.expect(NotificationChoice.silence(true, at: url), "written")
            suite.expect(NotificationChoice.isSilenced(at: url), "read back")
            suite.expect(NotificationChoice.isSilenced(at: url), "read back a second time")
        }

        suite.test("switching them on again takes the choice off the disk rather than recording it") {
            suite.expect(NotificationChoice.silence(true, at: url), "silenced")
            suite.expect(NotificationChoice.silence(false, at: url), "switched back on")
            suite.expect(!NotificationChoice.isSilenced(at: url), "speaks again")
            suite.expect(
                !FileManager.default.fileExists(atPath: url.path),
                "nothing must be left for a later release to read"
            )
        }

        suite.test("choosing the same thing twice is not an error either way") {
            suite.expect(NotificationChoice.silence(true, at: url), "silenced")
            suite.expect(NotificationChoice.silence(true, at: url), "silenced again")
            suite.expect(NotificationChoice.isSilenced(at: url), "still silent")
            suite.expect(NotificationChoice.silence(false, at: url), "switched on")
            suite.expect(NotificationChoice.silence(false, at: url), "switched on again")
            suite.expect(!NotificationChoice.isSilenced(at: url), "still speaking")
        }

        // What is inside the file is a note for whoever opens it. The app reads the choice off
        // the file being there, so a note somebody has scribbled over does not turn into a
        // half-answered question.
        suite.test("whatever is written inside the file, its being there is the choice") {
            try? Data("edited by hand\n".utf8).write(to: url, options: .atomic)
            suite.expect(NotificationChoice.isSilenced(at: url), "silent")
            try? Data().write(to: url, options: .atomic)
            suite.expect(NotificationChoice.isSilenced(at: url), "silent with an empty file")
            suite.expect(NotificationChoice.silence(false, at: url), "switched on")
        }

        suite.test("the note names the day it was made and how to undo it") {
            let moment = Date(timeIntervalSince1970: 1_789_000_000)
            suite.expect(NotificationChoice.silence(true, at: url, on: moment), "written")
            let note = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            suite.expect(
                note.contains(ISO8601DateFormatter().string(from: moment)),
                "the file must say when the app was asked to be quiet: \(note)"
            )
            suite.expect(
                note.lowercased().contains("delete this file"),
                "somebody who finds this file must be told how to undo it: \(note)"
            )
            suite.expect(NotificationChoice.silence(false, at: url), "switched on")
        }

        suite.test("a directory that is not there yet is made rather than failed over") {
            let nested = NotificationChoice.url(in: directory.appendingPathComponent("made-on-the-way"))
            suite.expect(NotificationChoice.silence(true, at: nested), "written")
            suite.expect(NotificationChoice.isSilenced(at: nested), "read back")
        }
    }

    // The choice lives with everything else this app keeps, which is what carries it across an
    // update: a copy dragged over the old one replaces the bundle and never touches this.
    suite.test("the choice is kept in the app's own directory, beside the marks that were moved") {
        let home = URL(fileURLWithPath: "/Users/nobody")
        let directory = SupportDirectory.url(home: home)
        suite.expectEqual(
            NotificationChoice.url(in: directory).deletingLastPathComponent().path,
            ThresholdChoicesStore.url(in: directory).deletingLastPathComponent().path,
            "the directory"
        )
        suite.expect(
            !NotificationChoice.url(in: directory).path.contains(".app/"),
            "a choice kept inside the bundle would be thrown away by the next copy dragged over it"
        )
    }

    // MARK: What the row says about it

    // The row has two things in it that answer different questions, and the risk is that one
    // starts speaking for the other: a tick about the channel read as "notifications work", or
    // a checkbox read as a permission. So the checkbox is named after what it does, and the
    // line under it says what did not change when it was unticked.
    suite.test("the checkbox says what it switches, and leaves the channel to the row") {
        let title = CheckupPhrasing.rows(for: CheckupState(
            sources: SetupState(connected: []),
            slot: .free,
            isAccessibilityTrusted: false,
            hasSessionRecords: false,
            notifications: nil,
            copy: RunningCopy(path: "/Applications/App.app", builtAt: nil, isAdHoc: true)
        )).first { $0.point == .notifications }?.title
        suite.expect(CheckupPhrasing.announceMarks.holds { !$0.isEmpty }, "a checkbox with a side of its label missing")
        suite.expect(
            CheckupPhrasing.announceMarks != title,
            "a checkbox labelled after the row it stands in says nothing about what it switches"
        )
        let silent = CheckupPhrasing.silenced
        suite.expect(
            silent.carries(Phrase("lights", "Огни")) && silent.carries(Phrase("panel", "панели")),
            "somebody switching this off has to be told what went with it: \(silent.shown)"
        )
        suite.expect(
            silent.carries(Phrase("channel", "канал")),
            "and that the mark beside the row is still answering its own question: \(silent.shown)"
        )
    }

    // MARK: Silence at the edge

    // The rule that makes switching the notifications back on safe: everything above the last
    // step runs exactly as it does for somebody who chose nothing, so the memory of what has
    // been accounted for never falls behind. A silence higher up would collect a backlog, and
    // the tick going back on would empty it onto the person in one go.
    let rules = BudgetRules(config: config)
    let window = 100_000
    let fill = config.windowFill

    func session(_ id: String, at percent: Double) -> ContextAssessment {
        rules.assess(
            SessionSnapshot(
                sessionID: id,
                service: .codex,
                contextTokens: Int((Double(window) * percent / 100).rounded()) + 1,
                contextWindowTokens: window
            )
        )
    }

    suite.test("a mark crossed while the app is quiet is not announced when it speaks again") {
        var dispatch = AlertDispatch()
        var screen: [BudgetAlert] = []

        /// One pass, as the app makes it: the rules are read and accounted for whatever the
        /// person chose, and the choice decides only what reaches the screen.
        func pass(_ assessment: ContextAssessment, silenced: Bool) {
            let fresh = dispatch.pending(limits: [], sessions: [assessment])
            guard !silenced else { return }
            screen.append(contentsOf: fresh)
        }

        pass(session("a", at: fill.notice - 5), silenced: false)

        pass(session("a", at: fill.elevated + 1), silenced: true)
        suite.expectEqual(screen.count, 0, "announced while the app was asked to be quiet")

        pass(session("a", at: fill.elevated + 2), silenced: false)
        suite.expectEqual(screen.count, 0, "the backlog of a quiet spell arriving at once")

        // And the pipeline is still live rather than deadened: the next mark is news.
        pass(session("a", at: fill.high + 1), silenced: false)
        suite.expect(
            screen.map(\.kind) == [.windowFill(percent: fill.high)],
            "the next mark crossed after speaking again: \(screen.map(\.kind))"
        )
    }

    // There is no way to exercise the edge itself — the banner is the system's — so what is
    // checked is the only reason it holds: the choice is consulted where the notification is
    // put on screen, and nowhere on the way there. A `guard` added in the model or in the
    // rules would read the same to a reviewer and quietly bring the backlog back.
    suite.test("the choice is read at the edge and nowhere above it") {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources", isDirectory: true)
        let files = (FileManager.default.enumerator(atPath: sources.path)?
            .compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") } ?? [])
            .sorted()
        suite.expect(files.count > 10, "found \(files.count) Swift files under \(sources.path)")

        let asking = files.filter { file in
            let path = sources.appendingPathComponent(file)
            guard let text = try? String(contentsOf: path, encoding: .utf8) else { return false }
            return text.contains("NotificationChoice")
        }
        suite.expect(
            asking == ["LLMInformBureau/Notifier.swift", "SessionHealthCore/NotificationChoice.swift"],
            "silence belongs to the last step before the screen, and to the file that keeps it: \(asking)"
        )
    }
}
