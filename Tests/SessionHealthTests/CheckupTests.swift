import Foundation
import Phrasing
import SessionHealthCore

/// The list the settings window shows: everything the app runs on that this Mac had to give it.
///
/// What is worth testing here is not that a permission is granted — nothing in a test can grant
/// one — but that the list tells the truth about whatever the machine answered: a tick only for
/// what is really there, a question mark for what macOS will not answer until the app tries, and
/// a line under every one of them saying what it costs while the answer is no.
func runCheckupTests(_ suite: TestSuite) {
    /// A machine that has given the app nothing.
    let bare = CheckupState(
        sources: SetupState(connected: []),
        slot: .free,
        isAccessibilityTrusted: false,
        hasSessionRecords: false,
        notifications: nil,
        copy: RunningCopy(path: "/Applications/LLM Inform Bureau.app", builtAt: nil, isAdHoc: true)
    )

    /// A machine that has given it everything it can be given.
    let settled = CheckupState(
        sources: SetupState(connected: Set(SetupState.Source.allCases)),
        slot: .ours,
        isAccessibilityTrusted: true,
        hasSessionRecords: true,
        notifications: .ownName,
        copy: RunningCopy(
            path: "/Applications/LLM Inform Bureau.app",
            builtAt: Date(timeIntervalSince1970: 1_789_000_000),
            isAdHoc: false
        )
    )

    func row(_ point: CheckupState.Point, of state: CheckupState) -> CheckupRow? {
        CheckupPhrasing.rows(for: state).first { $0.point == point }
    }

    // MARK: Every line is there, and every line says something

    suite.test("the checkup shows every point it knows about, in its own order") {
        for state in [bare, settled] {
            let rows = CheckupPhrasing.rows(for: state)
            suite.expectEqual(rows.count, CheckupState.Point.allCases.count, "rows")
            suite.expect(
                rows.map(\.point) == CheckupState.Point.allCases,
                "the list must keep the declared order, got \(rows.map(\.point.rawValue))"
            )
            for row in rows {
                suite.expect(!row.title.isEmpty, "\(row.point.rawValue): a row with no title")
                suite.expect(!row.detail.isEmpty, "\(row.point.rawValue): nothing says what this is for")
                suite.expectEqual(row.standing, state.standing(of: row.point), "\(row.point.rawValue) standing")
            }
        }
    }

    // The three sources were the half of this list that already existed. A second wording for
    // them would be the checkup quietly forking the one thing the panel and the README also say.
    suite.test("the three sources keep the words the first run already had") {
        for state in [bare, settled] {
            let items = Briefing.items(for: state.sources)
            for item in items {
                guard let point = CheckupState.Point.allCases.first(where: { $0.source == item.source }) else {
                    suite.expect(false, "no checkup line for the source \(item.source.rawValue)")
                    continue
                }
                let line = row(point, of: state)
                suite.expectEqual(line?.title, item.title, "\(item.source.rawValue) title")
                suite.expectEqual(line?.detail, item.detail, "\(item.source.rawValue) detail")
                suite.expectEqual(
                    line?.standing,
                    item.isConnected ? .given : .missing,
                    "\(item.source.rawValue) standing"
                )
            }
        }
    }

    suite.test("every source the app reads has a line of its own in the checkup") {
        for source in SetupState.Source.allCases {
            suite.expect(
                CheckupState.Point.allCases.contains { $0.source == source },
                "the source \(source.rawValue) is missing from the checkup"
            )
        }
    }

    // MARK: What unfolds the list

    suite.test("a machine with nothing missing leaves the list folded") {
        suite.expect(!settled.hasSomethingMissing, "nothing here is missing")
        suite.expect(bare.hasSomethingMissing, "a bare machine has plenty missing")
    }

    // The two lines that state a fact must never be what opens the list: neither of them is
    // something to act on, and a window that unfolded the whole list to show a path would be
    // asking for attention it has no use for.
    suite.test("a line that only states a fact never counts as missing") {
        for point in [CheckupState.Point.openAtLogin, .runningCopy] {
            for state in [bare, settled] {
                suite.expectEqual(state.standing(of: point), .stated, "\(point.rawValue) on a \(state == bare ? "bare" : "settled") machine")
            }
        }
    }

    // MARK: The slot

    suite.test("the slot reads as held whichever copy of this app is in it") {
        for slot in [StatusLineSlotState.ours, .oursElsewhere] {
            let state = with(settled, slot: slot)
            suite.expectEqual(state.standing(of: .statusLineSlot), .given, "\(slot)")
        }
    }

    suite.test("a slot that is not this app's names the button that would take it") {
        for slot in [StatusLineSlotState.free, .somebodyElse("~/bin/my-status-line")] {
            let state = with(bare, slot: slot)
            suite.expectEqual(state.standing(of: .statusLineSlot), .missing, "\(slot)")
            let detail = row(.statusLineSlot, of: state)?.detail ?? ""
            suite.expect(detail.contains(Briefing.connectAction), "\(slot): \(detail)")
        }
    }

    // Somebody's own command is kept and called; saying so is the difference between an offer
    // and a threat to overwrite their config.
    suite.test("somebody else's command is quoted in the line about it") {
        let command = "~/bin/my-status-line --short"
        let detail = row(.statusLineSlot, of: with(bare, slot: .somebodyElse(command)))?.detail ?? ""
        suite.expect(detail.contains(command), "the command must be shown as it is written: \(detail)")
    }

    // Nothing is written to a file this app cannot read, and the checkup must not offer a
    // button that would pretend otherwise.
    suite.test("an unreadable settings file names itself and offers nothing") {
        let path = "/Users/someone/.claude/settings.json"
        let line = row(.statusLineSlot, of: with(bare, slot: .unreadable(path)))
        suite.expectEqual(line?.standing, .missing, "standing")
        suite.expect(line?.detail.contains(path) == true, "the file must be named: \(line?.detail ?? "—")")
        suite.expect(
            line?.detail.contains(Briefing.connectAction) != true,
            "nothing is written to a file this app cannot read: \(line?.detail ?? "—")"
        )
    }

    // MARK: Accessibility, and the tick that belongs to another build

    suite.test("accessibility that was given offers no settings pane") {
        let line = row(.accessibility, of: settled)
        suite.expectEqual(line?.standing, .given, "standing")
        suite.expectEqual(line?.settings, nil, "a permission already given has no pane to open")
    }

    suite.test("accessibility that is missing sends the person to its own pane") {
        let line = row(.accessibility, of: bare)
        suite.expectEqual(line?.standing, .missing, "standing")
        suite.expectEqual(line?.settings, .accessibility, "pane")
    }

    // The one case where the system's own pane lies to a person's face: signed ad-hoc, the
    // tick from the build before is still there and grants nothing. A checkup that said
    // "not given" and stopped would be arguing with what they can see.
    suite.test("an ad-hoc copy explains a tick that belongs to the version before it") {
        let adHoc = row(.accessibility, of: bare)?.detail ?? ""
        suite.expect(
            adHoc.contains(Wording.tickFromAnEarlierBuild),
            "an ad-hoc copy must explain the stale tick: \(adHoc)"
        )
        let signed = row(.accessibility, of: with(bare, copy: RunningCopy(
            path: bare.copy.path,
            builtAt: bare.copy.builtAt,
            isAdHoc: false
        )))?.detail ?? ""
        suite.expect(
            !signed.contains(Wording.tickFromAnEarlierBuild),
            "a properly signed copy keeps its permissions and must not send anybody to undo a working tick: \(signed)"
        )
    }

    // MARK: Automation, which macOS will not answer for

    // The one permission the system has no question for: there is no call that says whether
    // controlling another app is allowed, and the only way to find out is to send an event.
    // Everything this app knows about that is what it tried once, at somebody's click, against
    // one terminal — so a tick or a gap drawn from it would be the app's guess wearing the
    // system's authority.
    suite.test("automation is settled on use whatever else the machine has answered") {
        for state in [bare, settled] {
            suite.expectEqual(state.standing(of: .automation), .settledOnUse, "\(state == bare ? "bare" : "settled")")
        }
    }

    // It has no answer to be missing, so it must never be what unfolds the list: a window that
    // opened itself on a question mark nobody can answer in advance would do it on every run.
    suite.test("automation never counts as something missing") {
        suite.expect(!settled.hasSomethingMissing, "a settled machine has an automation row too")
    }

    // The row a person reads while nothing has gone wrong yet. It has to say what the app will
    // ask for and when — the click is the moment — and where the answer ends up, because a
    // refusal given months ago leaves nothing else that would tell them.
    suite.test("automation says what it is for, when it is asked and where the answer is kept") {
        let line = row(.automation, of: bare)
        suite.expectEqual(line?.settings, .automation, "pane")
        let detail = line?.detail ?? ""
        for word in ["Terminal.app", "iTerm2", "click"] {
            suite.expect(detail.contains(word), "the row must name \(word): \(detail)")
        }
        suite.expectEqual(row(.automation, of: settled)?.detail, detail, "nothing about it changes with the machine")
    }

    // Both permissions a click can need have a row now, and each sends the person to the pane
    // where that answer is actually kept. A row that offered the other one would be worse than
    // no row: the pane it opens lists the app under a tick that means something else.
    suite.test("every permission a click can need has a checkup row that opens its own pane") {
        for permission in [TerminalRaise.Permission.accessibility, .automation] {
            let rows = CheckupPhrasing.rows(for: bare).filter { $0.settings == permission.pane }
            suite.expectEqual(rows.count, 1, "\(permission) is offered by \(rows.map(\.point.rawValue))")
        }
    }

    // MARK: Notifications, which have no tick to show

    suite.test("notifications say they are settled on first use, and offer no pane before that") {
        let line = row(.notifications, of: bare)
        suite.expectEqual(line?.standing, .settledOnUse, "standing")
        suite.expectEqual(line?.settings, nil, "there is no name to look for yet")
    }

    suite.test("a notification sent through osascript says whose name it arrives under") {
        let line = row(.notifications, of: with(settled, notifications: .scriptEditor))
        suite.expectEqual(line?.standing, .given, "standing")
        suite.expectEqual(line?.settings, .notifications, "pane")
        suite.expect(
            line?.detail.contains("Script Editor") == true,
            "the name in Notification settings is the whole point: \(line?.detail ?? "—")"
        )
    }

    // MARK: Which copy is running

    // The reason this line exists: two bundles of the same name, one of them in the menu bar,
    // and a privacy pane that lists them as one name. The path and the build date are what
    // tell them apart, so both have to reach the row.
    suite.test("the running copy is named by its path and the date it was built") {
        let built = Date(timeIntervalSince1970: 1_789_000_000)
        let here = with(settled, copy: RunningCopy(path: "/Applications/App.app", builtAt: built, isAdHoc: true))
        let there = with(settled, copy: RunningCopy(
            path: "/Users/someone/build/App.app",
            builtAt: built.addingTimeInterval(-3600),
            isAdHoc: true
        ))

        let one = row(.runningCopy, of: here)?.detail ?? ""
        let other = row(.runningCopy, of: there)?.detail ?? ""
        suite.expect(one.contains("/Applications/App.app"), "the path must be shown: \(one)")
        suite.expect(one.contains(TimeDisplay.moment(built)), "the build date must be shown: \(one)")
        suite.expect(one != other, "two copies of the same name must not read alike")
    }

    suite.test("a build date that could not be read says so rather than inventing one") {
        let detail = row(.runningCopy, of: bare)?.detail ?? ""
        suite.expect(!detail.isEmpty, "the row must still name the copy")
        suite.expect(detail.contains(bare.copy.path), "the path is known even when the date is not: \(detail)")
    }

    // MARK: The panes themselves

    // A pane identifier that stops working fails silently — System Settings opens its front
    // page and the person is left looking for a list nobody named. Nothing at runtime notices,
    // so this is where it is noticed.
    suite.test("every settings pane has a URL that opens System Settings") {
        for pane in SystemSettingsPane.allCases {
            guard let url = pane.url else {
                suite.expect(false, "\(pane.rawValue) has no URL")
                continue
            }
            suite.expectEqual(url.scheme, "x-apple.systempreferences", "\(pane.rawValue) scheme")
        }
        suite.expect(
            Set(SystemSettingsPane.allCases.map { $0.url }).count == SystemSettingsPane.allCases.count,
            "two panes share a URL, so one of them opens the wrong list"
        )
    }

    suite.test("each permission a click can need is kept in its own pane") {
        suite.expectEqual(TerminalRaise.Permission.accessibility.pane, .accessibility, "accessibility")
        suite.expectEqual(TerminalRaise.Permission.automation.pane, .automation, "automation")
    }

    suite.test("the button that opens a pane is named after the pane it opens") {
        let names = SystemSettingsPane.allCases.map(Wording.openSettings)
        suite.expect(Set(names).count == names.count, "two panes share a button name: \(names)")
        for name in names { suite.expect(!name.isEmpty, "a button with no name") }
        suite.expectEqual(
            Wording.permissionSettings(.accessibility),
            Wording.openSettings(.accessibility),
            "the panel and the checkup must call the same pane the same thing"
        )
    }

    // MARK: Opening the window asks the machine nothing

    // The rule of this whole list: a window opened to find out what the app is doing must not
    // put a permission dialog on screen. There is no way to exercise that — the dialog is the
    // system's — so what is checked is the only reason it holds: the one call that prompts is
    // made in one file, by a click that needed the answer.
    suite.test("the prompting form of the accessibility check lives in exactly one file") {
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

        let prompting = files.filter { file in
            let path = sources.appendingPathComponent(file)
            guard let text = try? String(contentsOf: path, encoding: .utf8) else { return false }
            return text.contains("AXIsProcessTrustedWithOptions")
        }
        suite.expect(
            prompting == ["LLMInformBureau/TerminalRaiser.swift"],
            "the dialog belongs to a click that needed the answer, and nowhere else: \(prompting)"
        )
    }
    // MARK: The roads into this list

    // Which row answers which dead end is the whole of `CheckupRoad`, and getting it wrong is
    // silent: the window opens, scrolls somewhere, and tells a person to go and fix something
    // that was never the problem.
    suite.test("a dead end in the panel leads to the row that explains it") {
        suite.expectEqual(CheckupRoad.limits(.codex).point(slot: .ours), .codex, "codex limits")
        suite.expectEqual(
            CheckupRoad.sessionClick.point(slot: .ours),
            .sessionRecords,
            "a session that cannot be brought up"
        )
        suite.expectEqual(
            CheckupRoad.permission(.accessibility).point(slot: .ours),
            .accessibility,
            "a click that could not look through the windows"
        )
        suite.expectEqual(
            CheckupRoad.permission(.automation).point(slot: .ours),
            .automation,
            "a click that could not ask for the tab"
        )
    }

    // The one dead end with two stories behind it: no limits because nothing holds the slot,
    // and no limits because the slot is held and nothing has reported yet. They are fixed in
    // different places, so they are different rows.
    suite.test("missing Claude limits lead to the slot, or to the source that holds it") {
        let unheld: [StatusLineSlotState] = [
            .free,
            .somebodyElse("~/.claude/statusline.sh"),
            .unreadable("~/.claude/settings.json")
        ]
        for slot in unheld {
            suite.expectEqual(CheckupRoad.limits(.claude).point(slot: slot), .statusLineSlot, "\(slot)")
        }
        for slot in [StatusLineSlotState.ours, .oursElsewhere] {
            suite.expectEqual(CheckupRoad.limits(.claude).point(slot: slot), .claudeLimits, "\(slot)")
        }
    }

    // A road to a row the list does not show would scroll the window to nothing at all — the
    // one failure of this feature a person could not tell from the app having ignored them.
    suite.test("every road lands on a row the list actually shows") {
        let roads: [CheckupRoad] = [
            .limits(.claude),
            .limits(.codex),
            .sessionClick,
            .permission(.accessibility),
            .permission(.automation)
        ]
        let shown = Set(CheckupPhrasing.rows(for: bare).map(\.point))
        for slot in [StatusLineSlotState.free, .ours, .oursElsewhere] {
            for road in roads {
                let point = road.point(slot: slot)
                suite.expect(shown.contains(point), "\(road) leads to \(point.rawValue), which is not in the list")
            }
        }
    }

    // MARK: What a click on a session runs on

    suite.test("the records row says what a click needs, whether they are there or not") {
        for state in [with(bare, records: false), with(settled, records: true)] {
            guard let row = row(.sessionRecords, of: state) else {
                suite.expect(false, "no row about the session records")
                continue
            }
            suite.expect(
                row.detail.contains("~/.claude/sessions"),
                "the file a click runs on is not named: \(row.detail)"
            )
            suite.expect(
                row.detail.contains("Codex"),
                "the one service whose sessions never click is not named: \(row.detail)"
            )
            suite.expect(row.settings == nil, "nothing on this Mac takes an answer about these")
        }
        suite.expect(
            row(.sessionRecords, of: with(bare, records: false))?.detail
                != row(.sessionRecords, of: with(bare, records: true))?.detail,
            "the row reads the same whether records are there or not"
        )
    }

    // Stated and never missing. The records appear while an interactive Claude Code is running
    // and at no other time: a dashed circle would make an ordinary quiet Mac look like a fault,
    // and — because a missing point is what unfolds this list — would open the checkup at every
    // person who had simply closed their sessions.
    suite.test("records nobody is writing are not a fault and do not unfold the list") {
        suite.expectEqual(
            with(settled, records: false).standing(of: .sessionRecords),
            .stated,
            "standing with no records"
        )
        suite.expectEqual(
            with(settled, records: true).standing(of: .sessionRecords),
            .stated,
            "standing with records"
        )
        suite.expect(
            !with(settled, records: false).hasSomethingMissing,
            "a Mac with no session running has nothing for this window to open itself about"
        )
    }

}

/// The same machine with one answer changed. Written out because `CheckupState` is a value
/// somebody assembled from five borders, and a test that rebuilt all five to move one of them
/// would say less about the move than about the rebuilding.
private func with(
    _ state: CheckupState,
    slot: StatusLineSlotState? = nil,
    records: Bool? = nil,
    notifications: NotificationChannel?? = nil,
    copy: RunningCopy? = nil
) -> CheckupState {
    CheckupState(
        sources: state.sources,
        slot: slot ?? state.slot,
        isAccessibilityTrusted: state.isAccessibilityTrusted,
        hasSessionRecords: records ?? state.hasSessionRecords,
        notifications: notifications ?? state.notifications,
        copy: copy ?? state.copy
    )
}
