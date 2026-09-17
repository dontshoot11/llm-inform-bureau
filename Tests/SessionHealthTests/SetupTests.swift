import Foundation
import AgentFiles
import Phrasing
import SessionHealthCore

/// What the app knows about itself before it has read a single number: which sources have
/// written anything, what the first run says about the ones that have not, and whether that
/// explanation has already been shown.
func runSetupTests(_ suite: TestSuite, config: ThresholdConfig) {
    withTemporaryDirectory(suite, named: "setup") { root in
        let status = makeDirectory(root, "claude-status", suite)
        let transcripts = makeDirectory(root, "projects", suite)
        let rollouts = makeDirectory(root, "sessions", suite)

        func inspect() -> SetupState {
            SetupInspector.inspect(
                statusDirectory: status,
                transcriptsDirectory: transcripts,
                rolloutsDirectory: rollouts
            )
        }

        suite.test("a machine where nothing has run has nothing connected") {
            let state = inspect()
            suite.expect(state.connected.isEmpty, "connected: \(state.connected)")
            suite.expect(!state.isComplete, "an empty machine must not read as complete")
        }

        // Each source is added on its own, because the interesting state is the partial one:
        // Codex reporting while Claude's limits are still missing is the normal first day.
        suite.test("a rollout on disk connects Codex and nothing else") {
            let day = makeDirectory(rollouts, "2026/09/15", suite)
            write("{}\n", to: day.appendingPathComponent("rollout-2026-09-15T10-00-00.jsonl"), suite)

            let state = inspect()
            suite.expect(state.isConnected(.codex), "Codex must be connected")
            suite.expect(!state.isConnected(.claudeSessions), "Claude sessions must still be missing")
            suite.expect(!state.isConnected(.claudeLimits), "Claude limits must still be missing")
        }

        suite.test("a transcript connects the Claude context budget") {
            let project = makeDirectory(transcripts, "-Users-someone-project", suite)
            write("{}\n", to: project.appendingPathComponent("a-session.jsonl"), suite)

            suite.expect(inspect().isConnected(.claudeSessions), "Claude sessions must be connected")
            suite.expect(!inspect().isConnected(.claudeLimits), "the slot is still not connected")
        }

        suite.test("a payload from the status line is what connects the Claude limits") {
            write("{}\n", to: status.appendingPathComponent("a-session.json"), suite)

            let state = inspect()
            suite.expect(state.isConnected(.claudeLimits), "Claude limits must be connected")
            suite.expect(state.isComplete, "everything has now written something: \(state.connected)")
        }

        // A file of the wrong kind next to the right ones is the shape of a stray editor
        // backup or a half-written download, and must not read as a connected source.
        suite.test("a file of another kind does not count as a source") {
            withTemporaryDirectory(suite, named: "setup-strays") { strays in
                let status = makeDirectory(strays, "claude-status", suite)
                let rollouts = makeDirectory(strays, "sessions", suite)
                write("{}\n", to: status.appendingPathComponent("notes.txt"), suite)
                write("{}\n", to: rollouts.appendingPathComponent("summary.jsonl"), suite)

                let state = SetupInspector.inspect(
                    statusDirectory: status,
                    transcriptsDirectory: strays.appendingPathComponent("missing-entirely"),
                    rolloutsDirectory: rollouts
                )
                suite.expect(state.connected.isEmpty, "connected on strays alone: \(state.connected)")
            }
        }
    }

    // MARK: What the first run says

    let nothing = SetupState(connected: [])
    let everything = SetupState(connected: Set(SetupState.Source.allCases))

    suite.test("the briefing covers every source, connected or not") {
        for state in [nothing, everything] {
            let items = Briefing.items(for: state)
            suite.expectEqual(items.count, SetupState.Source.allCases.count, "items")
            suite.expectEqual(Set(items.map(\.source)), Set(SetupState.Source.allCases), "sources")
            for item in items {
                suite.expect(item.title.holds { !$0.isEmpty }, "an item with a side of its title missing")
                suite.expect(item.detail.holds { !$0.isEmpty }, "\(item.title.shown): no detail")
            }
        }
    }

    // The one source that needs a person, and the only sentence in the app that sends them
    // somewhere. If it stops naming the button, the first run stops being useful.
    suite.test("the missing Claude limits name what connects them") {
        let limits = Briefing.items(for: nothing).first { $0.source == .claudeLimits }
        suite.expect(limits?.isConnected == false, "must read as not connected")
        suite.expect(
            limits?.detail.carries(Briefing.connectAction) == true,
            "detail: \(limits?.detail.shown ?? "—")"
        )
    }

    suite.test("the sources that connect themselves never send anybody anywhere") {
        for item in Briefing.items(for: nothing) where item.source != .claudeLimits {
            suite.expect(
                !item.detail.carries(Briefing.connectAction),
                "\(item.title.shown) offers a button it does not need: \(item.detail.shown)"
            )
        }
    }

    suite.test("a connected source is not told how to connect itself") {
        for item in Briefing.items(for: everything) {
            suite.expect(item.isConnected, "\(item.title.shown) reads as missing on a complete machine")
            suite.expect(
                !item.detail.carries(Briefing.connectAction),
                "\(item.title.shown) still says how to connect itself: \(item.detail.shown)"
            )
        }
    }

    // The same line AGENTS.md draws for notifications: the app reports what it read, and
    // never grades the session.
    // Both sides, because a promise the English half does not make is not one the Russian half
    // may make instead.
    suite.test("nothing in the briefing claims to have measured quality, in either language") {
        var lines: [Phrase] = [
            CheckupPhrasing.title, CheckupPhrasing.intro, CheckupPhrasing.closing,
            Briefing.marksTitle, Briefing.scaleHelp(config)
        ]
        lines += Briefing.levelKey.map(\.meaning)
        lines += Briefing.marks(of: config).flatMap { [$0.title, $0.what, $0.origin].compactMap { $0 } }
        lines += Briefing.items(for: nothing).flatMap { [$0.title, $0.detail] }
        lines += Briefing.items(for: everything).flatMap { [$0.title, $0.detail] }
        for side in [lines.map(\.english).joined(separator: " "), lines.map(\.russian).joined(separator: " ")] {
            let claims = QualityClaims.found(in: side)
            suite.expect(claims.isEmpty, "a claim about the answers themselves — \(claims) — in: \(side)")
        }
    }

    // A scale is shown as the lights it turns on rather than described, so what a test can
    // check is that every mark in the config reaches the window with the right light beside it.
    // A step lost here would leave the window quietly describing a scale the app has stopped
    // using — the one failure this whole list of marks exists to prevent.
    suite.test("each scale mark reaches the window with the light it turns on") {
        let shown = Briefing.marks(of: config)

        // Found by the mark it is rather than by what it is called: the title is a phrase with
        // two sides now, and which side a test reads is not what this one is about.
        for (mark, marks) in [(ThresholdMark.windowFill, config.windowFill), (.limitUsage, config.limitUsage)] {
            guard let note = shown.first(where: { $0.mark == mark }) else {
                suite.expect(false, "no mark for \(mark.rawValue)")
                continue
            }
            let title = mark.rawValue
            suite.expect(
                note.scale.map(\.percent) == [marks.notice, marks.elevated, marks.high],
                "\(title): the window must show the config's own marks, got \(note.scale.map(\.percent))"
            )
            suite.expect(
                note.scale.map(\.level) == [.notice, .elevated, .high],
                "\(title): each mark must carry the light it turns on, got \(note.scale.map(\.level))"
            )
        }
    }

    // The other half of the same list: a mark that is one number has no lights to show, and
    // the window draws it as a field. A scale step appearing here would be the window offering
    // a bar for something that is not a range.
    suite.test("every mark that is one number reaches the window with no scale on it") {
        let shown = Briefing.marks(of: config)

        for mark in ThresholdMark.minutes {
            guard let note = shown.first(where: { $0.mark == mark }) else {
                suite.expect(false, "\(mark.rawValue) is missing from the window")
                continue
            }
            suite.expect(note.scale.isEmpty, "\(mark.rawValue): a number is not a scale")
            suite.expect(note.title.holds { !$0.isEmpty }, "\(mark.rawValue): a mark with a side of its title missing")
            suite.expect(note.what.holds { !$0.isEmpty }, "\(mark.rawValue): a side says nothing about what this number does")
            suite.expect(config.duration(of: mark) != nil, "\(mark.rawValue): no duration in the config")
        }

        // And the mark that decides nothing a person chooses stays out of the window.
        suite.expect(
            !shown.contains { $0.mark == .limitWindowNearlyReset },
            "the quiet rule about a resetting window is not a setting"
        )
    }

    // The line that used to disappear the moment somebody dragged a handle. What a mark decides
    // is about the mark and not about the number standing on it, so moving the number cannot
    // make it untrue — and a window that took it away left three fields of minutes with nothing
    // but their titles, which is exactly the reader who has just changed something and wants to
    // know what.
    suite.test("every mark says what it decides, whether the app placed it or the reader did") {
        let mine = ThresholdChoices()
            .choosing(.windowFill, MarkScale(notice: 25, elevated: 45, high: 85) ?? MarkScale(of: config.windowFill))
            .choosing(.limitUsage, MarkScale(notice: 15, elevated: 35, high: 75) ?? MarkScale(of: config.limitUsage))
            .choosing(.abandonedWait, minutes: 25)
            .choosing(.attentionNotice, minutes: 5)
            .choosing(.sessionActivity, minutes: 45)
        let moved = Briefing.marks(of: mine.applied(to: config))

        suite.expectEqual(moved.count, Briefing.marks(of: config).count, "marks shown")
        for note in moved {
            suite.expect(note.isChosen, "\(note.mark.rawValue): the fixture moved every mark")
            suite.expect(note.what.holds { !$0.isEmpty }, "\(note.mark.rawValue): a side says nothing about what this mark decides")
            suite.expectEqual(note.origin, MarkNote.chosen, "\(note.mark.rawValue) origin")
            suite.expect(note.source == nil, "\(note.mark.rawValue): nothing published backs a moved mark")
        }

        // And a mark nobody moved keeps saying both things — what it decides and where its
        // number came from, which is the half the reader takes over by moving it.
        for note in Briefing.marks(of: config) {
            suite.expect(note.what.holds { !$0.isEmpty }, "\(note.mark.rawValue): a side says nothing about what this mark decides")
            suite.expect(
                note.origin != MarkNote.chosen,
                "\(note.mark.rawValue): a shipped mark must not claim the reader chose it"
            )
        }
    }

    // A colour nobody explained is a colour the reader gives a meaning of their own, and the
    // marks underneath say only where it starts. Green is in the key for exactly that reason:
    // it is the colour the widget spends most of its life in.
    suite.test("every colour the widget can draw is explained above the marks") {
        let explained = Briefing.levelKey.map(\.level)
        for level in [BudgetLevel.normal, .notice, .elevated, .high] {
            suite.expect(explained.contains(level), "no key entry for \(level)")
        }
        for entry in Briefing.levelKey {
            suite.expect(entry.meaning.holds { !$0.isEmpty }, "\(entry.level): an empty side explains nothing")
        }
    }

    // MARK: A machine with only one of the two agents

    // Not everyone runs both. A missing agent must read as "nothing here", in words, and must
    // not take the other one down with it or turn into an error about a broken source.
    withTemporaryDirectory(suite, named: "one-agent") { root in
        let nowhere = root.appendingPathComponent("never-installed", isDirectory: true)
        let claudeProjects = makeDirectory(root, "projects", suite)
        let project = makeDirectory(claudeProjects, "-Users-someone-project", suite)
        let transcript = project.appendingPathComponent("session.jsonl")
        write(
            """
            {"type":"assistant","timestamp":"\(iso(Date()))","message":{"model":"claude-opus-5",\
            "usage":{"input_tokens":1000,"cache_read_input_tokens":40000,"cache_creation_input_tokens":0}}}

            """,
            to: transcript,
            suite
        )
        touch(transcript, at: Date(), suite)

        let reading = UsageReader(
            claudeTranscripts: ClaudeTranscriptStore(projectsDirectory: claudeProjects),
            claudeStatus: ClaudeStatusStore(directory: nowhere),
            codexRollouts: CodexRolloutStore(sessionsDirectory: nowhere)
        ).read(config: .builtIn)

        suite.test("the agent that is installed reads normally with the other one absent") {
            suite.expectEqual(reading.claudeSessions.value?.count, 1, "Claude sessions")
        }

        suite.test("the reading knows which agents are on this machine") {
            suite.expect(reading.isInstalled(.claude), "Claude has a directory here")
            suite.expect(!reading.isInstalled(.codex), "Codex has none and must not read as installed")
        }

        // The panel says one thing for a missing agent and another for an idle one, and this
        // is the fact it decides on. An idle agent that read as missing would tell someone to
        // install what they already have.
        suite.test("an agent whose tree exists but is empty still reads as installed") {
            let empty = makeDirectory(root, "codex-installed-but-idle", suite)
            let idle = UsageReader(
                claudeTranscripts: ClaudeTranscriptStore(projectsDirectory: claudeProjects),
                claudeStatus: ClaudeStatusStore(directory: nowhere),
                codexRollouts: CodexRolloutStore(sessionsDirectory: empty)
            ).read(config: .builtIn)

            suite.expect(idle.isInstalled(.codex), "an empty tree means installed and idle, not absent")
            let idleSaid = idle.codexSessions.explanation
            suite.expect(
                idleSaid?.english.lowercased().contains("yet") == true
                    && idleSaid?.russian.lowercased().contains("пока") == true,
                "an idle agent waits: \(idleSaid?.shown ?? "(nothing)")"
            )
        }

        suite.test("an agent that was never installed says so in words, and is not an error") {
            suite.expect(reading.codexSessions.value == nil, "an absent agent must not report sessions")
            suite.expect(
                reading.codexSessions.explanation?.holds { !$0.isEmpty } == true,
                "an absent agent must explain itself: \(reading.codexSessions.explanation?.shown ?? "(nothing)")"
            )
            if case .unavailable(let why) = reading.codexSessions {
                suite.expect(false, "never installed must not read as a broken source: \(why.shown)")
            }
            if case .unavailable(let why) = reading.codexLimits {
                suite.expect(false, "never installed must not read as broken limits: \(why.shown)")
            }
            suite.expect(reading.codexLimits.value == nil, "an absent agent must not report limits")
        }
    }

    // MARK: Showing it once

    withTemporaryDirectory(suite, named: "welcome") { home in
        let record = WelcomeRecord(url: WelcomeRecord.defaultURL(home: home))

        suite.test("the explanation is due on a machine that has never seen it") {
            suite.expect(!record.hasBeenShown, "nothing has been shown yet")
        }

        suite.test("recording it creates the app's directory along the way") {
            record.markShown()
            suite.expect(record.hasBeenShown, "the record must survive being written")
            suite.expect(
                record.url.path.hasPrefix(SupportDirectory.url(home: home).path),
                "the record must live in the app's own directory: \(record.url.path)"
            )
        }
    }
}

/// An ISO-8601 stamp, the way the transcripts carry one.
private func iso(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

/// Sets a fixture's modification date: what the widget shows depends on when a file was last
/// written, so it is part of the fixture.
private func touch(_ url: URL, at date: Date, _ suite: TestSuite) {
    do {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    } catch {
        suite.expect(false, "could not touch \(url.path): \(error)")
    }
}

/// Writes a fixture file, failing the case rather than throwing when it cannot.
private func write(_ contents: String, to url: URL, _ suite: TestSuite) {
    do {
        try Data(contents.utf8).write(to: url)
    } catch {
        suite.expect(false, "could not write \(url.path): \(error)")
    }
}
