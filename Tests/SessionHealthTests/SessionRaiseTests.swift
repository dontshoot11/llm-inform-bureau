import Darwin
import Foundation
import AgentFiles
import Phrasing
import SessionHealthCore

/// The road from a row in the panel to the window a session is running in.
///
/// Three things are worth cases of their own here, and none of them is the raising itself —
/// that is one call to the system and cannot be tested without a window on screen. What can be
/// tested is everything that decides *whether* to make it: what a process says about itself,
/// what the join is allowed to carry across from a record, and how far a click can get in a
/// given terminal.
func runSessionRaiseTests(_ suite: TestSuite, config: ThresholdConfig) {
    let now = fixtureNow

    // MARK: What a process says about itself
    //
    // Measured against this very test run, which is the one process these cases can be sure
    // exists. Nothing here is a fixture: a hand-written process table would be testing the
    // fixture, and the whole point of this reader is that it asks the kernel.

    let ourselves = getpid()

    suite.test("a live process says when it started") {
        guard let started = SessionProcess.startedAt(ourselves) else {
            suite.expect(false, "this test's own process has no start time")
            return
        }
        let age = Date().timeIntervalSince(started)
        suite.expect(age >= 0, "the test run did not start in the future — \(age)s")
        suite.expect(age < 3600, "and it started within the hour — \(age)s")
    }

    suite.test("a pid nothing is using says nothing") {
        // Past any pid the kernel hands out, so there is nothing to be flaky about.
        suite.expect(SessionProcess.startedAt(Int32.max) == nil, "no start time for no process")
        suite.expect(
            !SessionProcess.isTheOne(Int32.max, startedAt: now),
            "and it is nobody's process, whatever moment it is asked about"
        )
    }

    suite.test("a process is the one its record named when the two start together") {
        guard let started = SessionProcess.startedAt(ourselves) else { return }
        suite.expect(
            SessionProcess.isTheOne(ourselves, startedAt: started),
            "its own start is its own start"
        )
        // The gap the tolerance is for: the CLI boots and writes its record a fraction of a
        // second later, measured at 0.43 s and 0.64 s on two live sessions.
        suite.expect(
            SessionProcess.isTheOne(ourselves, startedAt: started.addingTimeInterval(1)),
            "a record written a second after the process started is still about it"
        )
        // And the case the tolerance exists to refuse: the same number, a different process.
        suite.expect(
            !SessionProcess.isTheOne(ourselves, startedAt: started.addingTimeInterval(600)),
            "a record about something that started ten minutes later is about something else"
        )
    }

    suite.test("the chain above a process starts with it and climbs") {
        let chain = SessionProcess.ancestors(of: ourselves)
        suite.expectEqual(chain.first, ourselves, "nearest first")
        suite.expect(chain.count > 1, "and something started this test run — \(chain)")
        suite.expect(!chain.contains(1), "the top is left out, not walked into — \(chain)")
        // Walked to the top rather than stopped at the first step that would not answer. The
        // difference is not academic: a session in Terminal.app sits under root-owned `login`,
        // and asking the kernel for the full account of a process this app does not own is
        // refused — which used to end the walk one step below the application.
        suite.expectEqual(
            chain.last.map { SessionProcess.ancestors(of: $0) },
            chain.last.map { [$0] },
            "the last step walked is one whose own parent is the top"
        )
        suite.expectEqual(
            SessionProcess.ancestors(of: ourselves, limit: 1),
            [ourselves],
            "and the walk is bounded, because a cycle in the table would otherwise hang a pass"
        )
    }

    // MARK: What the join carries across
    //
    // The pid travels on a different rule than the pause sign, and these cases are about that
    // difference. `isTheOne` is handed in, because the alternative is a test that passes or
    // fails depending on which processes this machine happens to be running.

    let session = SessionSnapshot(
        sessionID: "abc",
        service: .claude,
        contextTokens: 40_000,
        contextWindowTokens: 200_000,
        lastActivityAt: now,
        replyWait: .waiting
    )
    let activity = SessionActivity(config: config)

    func join(
        _ snapshots: [SessionSnapshot],
        _ records: [ClaudeSessionRecord],
        alive: Bool = true,
        now: Date = fixtureNow
    ) -> [SessionSnapshot] {
        let reading = UsageReader.withRecords(
            .value(snapshots),
            from: records,
            activity: activity,
            now: now,
            isTheOne: { _, _ in alive }
        )
        return reading.value ?? []
    }

    func record(
        pid: Int32,
        status: String = "busy",
        statusUpdatedAt: Date = fixtureNow,
        session: String = "abc"
    ) -> ClaudeSessionRecord {
        ClaudeSessionRecord(
            sessionID: session,
            asking: status == "waiting" ? .question : nil,
            statusUpdatedAt: statusUpdatedAt,
            pid: pid,
            startedAt: statusUpdatedAt.addingTimeInterval(-600)
        )
    }

    suite.test("a live process reaches the row it belongs to") {
        let joined = join([session], [record(pid: 4242)])
        suite.expectEqual(joined.first?.processID, 4242, "the pid of the record's process")
        suite.expectEqual(joined.first?.replyWait, .waiting, "and nothing else about the row moved")
    }

    suite.test("a process that is not the one the record named reaches nobody") {
        let joined = join([session], [record(pid: 4242)], alive: false)
        suite.expect(joined.first?.processID == nil, "no pid, so the row promises no window")
    }

    suite.test("a record too old to raise a pause sign still leads to a window") {
        // The two rules are deliberately apart: an hour-old record cannot claim anybody is
        // waiting — nothing rewrites it while the person is away — but its process either
        // answers for itself or does not, and this one does.
        let stale = now.addingTimeInterval(-3 * 3600)
        let joined = join(
            [session],
            [record(pid: 4242, status: "waiting", statusUpdatedAt: stale)]
        )
        suite.expectEqual(joined.first?.processID, 4242, "the pid still travels")
        suite.expectEqual(joined.first?.replyWait, .waiting, "and the stale record raises no sign")
    }

    suite.test("the newest record of a session is the one whose process is used") {
        let joined = join(
            [session],
            [
                record(pid: 111, statusUpdatedAt: now.addingTimeInterval(-120)),
                record(pid: 222, statusUpdatedAt: now)
            ]
        )
        suite.expectEqual(joined.first?.processID, 222, "the process still running the session")
    }

    suite.test("a subagent gets no process: it has no window of its own") {
        let agent = SessionSnapshot(
            sessionID: "abc",
            service: .claude,
            contextTokens: 10_000,
            contextWindowTokens: 200_000,
            lastActivityAt: now,
            subagent: SubagentOrigin(
                parentSessionID: "abc",
                type: "Explore",
                task: "look around",
                inheritsParentWindow: true
            )
        )
        let joined = join([agent], [record(pid: 4242)])
        suite.expect(joined.first?.processID == nil, "the row of an agent leads nowhere")
    }

    suite.test("a session with no record of its own is left exactly as it was") {
        let joined = join([session], [record(pid: 4242, session: "somebody-else")])
        suite.expect(joined.first?.processID == nil, "no record, no pid")
        suite.expectEqual(joined.first?.replyWait, .waiting, "and no claim about who is waiting")
    }

    // MARK: How far a click can get

    suite.test("Terminal.app is asked for the tab, by the terminal device") {
        guard case .tab(let script) = TerminalRaise.plan(owner: "com.apple.Terminal", tty: "ttys001") else {
            suite.expect(false, "Terminal.app can be asked for a tab")
            return
        }
        suite.expect(script.contains("/dev/ttys001"), "the device as AppleScript names it")
        suite.expect(script.contains("com.apple.Terminal"), "addressed by bundle id, not by name")
        suite.expect(script.contains("tabs of w"), "walking tabs, not opening one")
        suite.expect(
            script.range(of: "activate")!.lowerBound > script.range(of: "selected of t")!.lowerBound,
            "the tab is chosen before the window is raised, so a refusal leaves the screen alone"
        )
    }

    suite.test("iTerm2 is asked for its session, which is where a tty lives there") {
        guard case .tab(let script) = TerminalRaise.plan(owner: "com.googlecode.iterm2", tty: "ttys009") else {
            suite.expect(false, "iTerm2 can be asked for a tab")
            return
        }
        suite.expect(script.contains("sessions of t"), "a tty belongs to a session in iTerm2")
        suite.expect(script.contains("/dev/ttys009"), "the device it is looking for")
    }

    suite.test("a terminal that cannot name its tabs is asked for the project's window") {
        suite.expectEqual(
            TerminalRaise.plan(owner: "com.microsoft.VSCode", tty: "ttys001", project: "olymp-static"),
            .window(titled: "olymp-static"),
            "an editor titles its windows after the folder open in them"
        )
        suite.expectEqual(
            TerminalRaise.plan(owner: "com.mitchellh.ghostty", tty: "ttys001", project: "olymp-static"),
            .window(titled: "olymp-static"),
            "and so does a terminal with no AppleScript dictionary"
        )
    }

    suite.test("without a project there is nothing to recognise a window by") {
        suite.expectEqual(
            TerminalRaise.plan(owner: "com.microsoft.VSCode", tty: "ttys001", project: nil),
            .app,
            "the application, which is the floor"
        )
        // A name of spaces would match every title there is, and the first window back would
        // be raised as though it had been recognised.
        suite.expectEqual(
            TerminalRaise.plan(owner: "com.microsoft.VSCode", tty: "ttys001", project: "  "),
            .app,
            "and a blank name is no name"
        )
    }

    suite.test("a terminal that can name its tabs is still asked for the tab") {
        guard case .tab = TerminalRaise.plan(
            owner: "com.apple.Terminal",
            tty: "ttys001",
            project: "olymp-static"
        ) else {
            suite.expect(false, "the tab is the closer answer, and it needs the lighter permission")
            return
        }
    }

    suite.test("a process with no controlling terminal has no tab to look for") {
        suite.expectEqual(
            TerminalRaise.plan(owner: "com.apple.Terminal", tty: nil),
            .app,
            "however capable the terminal, there is nothing to match a tab against"
        )
    }

    suite.test("a process nothing owns raises nothing at all") {
        suite.expectEqual(
            TerminalRaise.plan(owner: nil, tty: "ttys001"),
            .nothing,
            "no application above it means no window to bring up"
        )
    }

    // MARK: What the panel says when the click stopped at the application
    //
    // The sentence about a tick already given is the one part of this road a person cannot
    // work out for themselves: the pane shows their tick, and it does nothing. It is said by a
    // copy signed ad-hoc and by no other, so both halves are worth a case.

    suite.test("an ad-hoc copy warns that a tick may belong to the version before") {
        let said = Wording.permissionOffer(.accessibility, signedAdHoc: true)
        suite.expect(
            said.carries(Phrase("version before this one", "прошлой версии")),
            "the pane's tick is named as the earlier one — \(said.shown)"
        )
        suite.expect(
            said.carries(Phrase("untick it and tick it again", "снимите и поставьте заново")),
            "and the person is told what to do about it — \(said.shown)"
        )
    }

    suite.test("a copy signed with a certificate keeps that sentence to itself") {
        let said = Wording.permissionOffer(.accessibility, signedAdHoc: false)
        suite.expect(
            said.carries(Phrase("allowed in Accessibility", "в разделе «Универсальный доступ»")),
            "what is missing is still named — \(said.shown)"
        )
        suite.expect(
            !said.carries(Phrase("untick", "снимите")),
            "and nobody is sent to undo a tick that works — \(said.shown)"
        )
    }

    suite.test("the tab's permission is not about ticks of earlier versions") {
        // Automation is kept per application asked about rather than per copy of this one, and
        // the sentence would be a guess dressed as an explanation.
        suite.expect(
            !Wording.permissionOffer(.automation, signedAdHoc: true).carries(Phrase("untick", "снимите")),
            "the automation answer says nothing about unticking"
        )
    }
}
