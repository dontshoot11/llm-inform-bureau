import Foundation
import AgentFiles
import Phrasing
import SessionHealthCore

/// Subagents of a Claude session: their own files, their own context, their own mark.
///
/// Claude Code writes a subagent into `<session>/subagents/agent-<id>.jsonl` with
/// `agent-<id>.meta.json` beside it. Everything in that file is a sidechain line — the very
/// thing a session's reading throws away — so the rule is not "skip sidechain lines" but "a
/// sidechain line is not the *session's* context": in the agent's own file it is all there is.
func runClaudeAgentTests(_ suite: TestSuite, config: ThresholdConfig) {
    let activity = SessionActivity(config: config)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let rules = BudgetRules(config: config)

    /// The agent lines of a subagent still working: it answered and asked for a tool, which is
    /// what a transcript of a turn in progress ends on.
    func working(tokens: Int, model: String = "claude-opus-5") -> [String] {
        [
            userPrompt("go and look", sidechain: true),
            assistant(input: 1, cacheCreation: 0, cacheRead: tokens - 1, sidechain: true, model: model)
        ]
    }

    func meta(type: String = "general-purpose", task: String = "Audit the PRD", model: String? = nil) -> String {
        var fields = [
            "\"agentType\":\"\(type)\"",
            "\"description\":\"\(task)\"",
            "\"toolUseId\":\"toolu_1\"",
            "\"spawnDepth\":1"
        ]
        if let model { fields.append("\"model\":\"\(model)\"") }
        return "{\(fields.joined(separator: ","))}"
    }

    /// One session with one subagent, and whatever the case wants to say about either.
    func sessionWithAgent(
        _ root: URL,
        _ name: String,
        sessionLines: [String] = [userPrompt("start"), assistant(input: 1, cacheCreation: 0, cacheRead: 50_000)],
        sessionModified: TimeInterval = 0,
        agentLines: [String],
        agentMeta: String?,
        agentModified: TimeInterval = 0
    ) -> URL {
        let directory = makeProjectDirectory(root, name, suite)
        writeTranscript(
            sessionLines,
            to: directory, named: "abc.jsonl", modified: now.addingTimeInterval(sessionModified), suite
        )
        writeSubagentTranscript(
            agentLines,
            to: directory, session: "abc", named: "agent-1.jsonl",
            modified: now.addingTimeInterval(agentModified), suite
        )
        if let agentMeta {
            writeSubagentMeta(agentMeta, to: directory, session: "abc", named: "agent-1.meta.json", suite)
        }
        return directory
    }

    func read(_ directory: URL, filesToScan: Int = 20) -> [SessionSnapshot] {
        ClaudeTranscriptStore(projectsDirectory: directory, filesToScan: filesToScan)
            .activeSessions(activity: activity, now: now).value ?? []
    }

    withTemporaryDirectory(suite, named: "claude-subagents") { root in
        suite.test("a subagent's file is its own context — the sidechain lines in it are counted") {
            let directory = sessionWithAgent(
                root, "own-context",
                agentLines: working(tokens: 90_000),
                agentMeta: meta()
            )

            let snapshots = read(directory)
            guard let agent = snapshots.first(where: { $0.isSubagent }) else {
                suite.expect(false, "expected a subagent, got \(snapshots.map(\.sessionID))")
                return
            }
            suite.expectEqual(agent.contextTokens, 90_000, "the agent's own context, from its own lines")
            suite.expectEqual(agent.service, .claude, "service")
            suite.expectEqual(agent.subagent?.parentSessionID, "abc", "the session that started it")
            suite.expectEqual(agent.subagent?.type, "general-purpose", "the kind of agent")
            suite.expectEqual(agent.subagent?.task, "Audit the PRD", "what it was asked to do")
            suite.expectEqual(agent.project, "llm-inform-bureau", "the project its session works in")

            let session = snapshots.first { !$0.isSubagent }
            suite.expectEqual(session?.contextTokens, 50_001, "and the session still reads as itself")
        }

        suite.test("a subagent with no metadata file is still a row, with a name of its own") {
            let directory = sessionWithAgent(
                root, "no-meta",
                agentLines: working(tokens: 40_000),
                agentMeta: nil
            )

            guard let agent = read(directory).first(where: { $0.isSubagent }) else {
                suite.expect(false, "expected the subagent to be listed anyway")
                return
            }
            suite.expect(agent.subagent?.type == nil, "nothing claims to know what kind of agent it is")
            suite.expect(agent.subagent?.task == nil, "nor what it was asked to do")
            suite.expectEqual(agent.contextTokens, 40_000, "its context is read from its transcript all the same")
            suite.expect(
                !Wording.subagentName(agent.subagent?.type).isEmpty,
                "and the panel has something to call it"
            )
        }

        suite.test("a session with no subagents directory is one session and no empty rows") {
            let directory = makeProjectDirectory(root, "no-agents", suite)
            writeTranscript(
                [userPrompt("start"), assistant(input: 1, cacheCreation: 0, cacheRead: 50_000)],
                to: directory, named: "abc.jsonl", modified: now, suite
            )

            let snapshots = read(directory)
            suite.expectEqual(snapshots.count, 1, "one session")
            suite.expect(!snapshots.contains { $0.isSubagent }, "and nothing standing in for an agent")
        }

        suite.test("a subagent that finished is gone at once, and its session stays") {
            // An agent's last line when it is done is its final answer, marked `end_turn`.
            // There is no cost line the way a session has one.
            let directory = sessionWithAgent(
                root, "finished",
                agentLines: [
                    userPrompt("go and look", sidechain: true),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 99_999, sidechain: true, stopReason: "end_turn")
                ],
                agentMeta: meta()
            )

            let snapshots = read(directory)
            suite.expect(!snapshots.contains { $0.isSubagent }, "the agent is over")
            suite.expectEqual(snapshots.map(\.sessionID), ["abc"], "the session it ran in is not")
        }

        suite.test("a subagent that was interrupted goes quiet rather than hanging about") {
            // An interrupted agent never writes a final answer, so nothing marks it finished.
            // The activity rule is what takes it off the list, the same as for a session.
            let interrupted = [userPrompt("go and look", sidechain: true), toolResult(sidechain: true)]
            let fresh = sessionWithAgent(
                root, "interrupted-fresh",
                agentLines: working(tokens: 30_000) + interrupted,
                agentMeta: meta()
            )
            suite.expect(read(fresh).contains { $0.isSubagent }, "still listed while it is fresh")

            let stale = sessionWithAgent(
                root, "interrupted-stale",
                agentLines: working(tokens: 30_000) + interrupted,
                agentMeta: meta(),
                agentModified: -86_400
            )
            suite.expect(!read(stale).contains { $0.isSubagent }, "and gone once it has been quiet for a day")
        }

        suite.test("a subagent does not outlive the session that started it") {
            let directory = sessionWithAgent(
                root, "session-gone",
                sessionModified: -86_400,
                agentLines: working(tokens: 30_000),
                agentMeta: meta()
            )
            suite.expectEqual(read(directory).count, 0, "the session is stale, so neither is shown")

            // And the rule itself, without the files: an agent whose session is not on the
            // list has nothing to be nested under, whatever its own file says.
            let orphan = SessionSnapshot(
                sessionID: "agent-1",
                service: .claude,
                contextTokens: 30_000,
                contextWindowTokens: 200_000,
                lastActivityAt: now,
                subagent: SubagentOrigin(parentSessionID: "gone", type: nil, task: nil, inheritsParentWindow: true)
            )
            suite.expectEqual(activity.active([orphan], now: now).count, 0, "an agent alone is not a row")
        }

        suite.test("subagent files do not spend the budget of transcripts to look at") {
            // The scan looks at the newest few files. Agent files are newer than the session
            // they belong to — one session with a few of them used to push other projects'
            // sessions out of the list entirely.
            let directory = makeProjectDirectory(root, "scan-budget", suite)
            writeTranscript(
                [userPrompt("start"), assistant(input: 1, cacheCreation: 0, cacheRead: 50_000)],
                to: directory, named: "abc.jsonl", modified: now.addingTimeInterval(-300), suite
            )
            for index in 1...3 {
                writeSubagentTranscript(
                    working(tokens: 10_000 * index),
                    to: directory, session: "abc", named: "agent-\(index).jsonl",
                    modified: now.addingTimeInterval(-60), suite
                )
            }
            writeTranscript(
                [userPrompt("start"), assistant(input: 1, cacheCreation: 0, cacheRead: 20_000)],
                to: directory, named: "zzz.jsonl", modified: now.addingTimeInterval(-600),
                project: "-Users-nobody-projects-elsewhere", suite
            )

            let snapshots = read(directory, filesToScan: 2)
            let sessions = snapshots.filter { !$0.isSubagent }.map(\.sessionID).sorted()
            suite.expectEqual(sessions, ["abc", "zzz"], "both projects' sessions")
            suite.expectEqual(snapshots.filter(\.isSubagent).count, 3, "and the agents besides")
        }

        suite.test("a session with more subagents than the scan allows shows the newest of them") {
            // The cap is what keeps one busy session from filling the panel; the session
            // itself is never the row that drops.
            let directory = makeProjectDirectory(root, "agent-cap", suite)
            writeTranscript(
                [userPrompt("start"), assistant(input: 1, cacheCreation: 0, cacheRead: 50_000)],
                to: directory, named: "abc.jsonl", modified: now.addingTimeInterval(-300), suite
            )
            for index in 1...3 {
                writeSubagentTranscript(
                    working(tokens: 10_000 * index),
                    to: directory, session: "abc", named: "agent-\(index).jsonl",
                    modified: now.addingTimeInterval(TimeInterval(-60 * (4 - index))), suite
                )
            }

            let snapshots = ClaudeTranscriptStore(projectsDirectory: directory, subagentsToScan: 2)
                .activeSessions(activity: activity, now: now).value ?? []
            suite.expectEqual(snapshots.filter(\.isSubagent).count, 2, "no more rows than the cap allows")
            suite.expectEqual(
                snapshots.filter(\.isSubagent).map(\.contextTokens).sorted(), [20_000, 30_000],
                "and the ones kept are the newest"
            )
            suite.expectEqual(snapshots.filter { !$0.isSubagent }.map(\.sessionID), ["abc"], "the session stays")
        }

        suite.test("a subagent reports no last request of its own") {
            // An agent is one request as far as the person who started it is concerned. The
            // turns inside it are not things they asked for, so there is no growth to show.
            let directory = sessionWithAgent(
                root, "no-growth",
                agentLines: [
                    userPrompt("go and look", sidechain: true),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 30_000, sidechain: true),
                    toolResult(sidechain: true),
                    userPrompt("and now this", sidechain: true),
                    assistant(input: 1, cacheCreation: 0, cacheRead: 90_000, sidechain: true)
                ],
                agentMeta: meta()
            )

            guard let agent = read(directory).first(where: { $0.isSubagent }) else {
                suite.expect(false, "expected the subagent")
                return
            }
            suite.expect(agent.turnGrowthTokens == nil, "growth is not reported for an agent")
        }

        // MARK: Which window an agent is measured against

        suite.test("a subagent runs on the session's model unless it was given one") {
            let inherited = sessionWithAgent(
                root, "inherits", agentLines: working(tokens: 30_000), agentMeta: meta()
            )
            suite.expect(
                read(inherited).first { $0.isSubagent }?.subagent?.inheritsParentWindow == true,
                "no model named means the session's model"
            )

            // A fork says so in as many words, and it is still the session's model.
            let forked = sessionWithAgent(
                root, "fork", agentLines: working(tokens: 30_000), agentMeta: meta(type: "fork", model: "inherit")
            )
            suite.expect(
                read(forked).first { $0.isSubagent }?.subagent?.inheritsParentWindow == true,
                "an explicit inherit is not an override"
            )

            let overridden = sessionWithAgent(
                root, "own-model", agentLines: working(tokens: 30_000), agentMeta: meta(model: "opus")
            )
            suite.expect(
                read(overridden).first { $0.isSubagent }?.subagent?.inheritsParentWindow == false,
                "a model named in the metadata is an override"
            )

            // The safety net: whatever the metadata says, an agent whose own lines name
            // another model is not on the session's model.
            let disagreeing = sessionWithAgent(
                root, "other-model",
                agentLines: working(tokens: 30_000, model: "claude-haiku-4-5"),
                agentMeta: meta()
            )
            suite.expect(
                read(disagreeing).first { $0.isSubagent }?.subagent?.inheritsParentWindow == false,
                "the model on its own lines disagrees with the session's"
            )
        }
    }

    // MARK: The window, once the wrapper has said how big the session's is

    let session = SessionSnapshot(
        sessionID: "s1",
        service: .claude,
        contextTokens: 100_000,
        contextWindowTokens: nil,
        project: "llm-inform-bureau"
    )

    func subagent(inherits: Bool, tokens: Int = 300_000) -> SessionSnapshot {
        SessionSnapshot(
            sessionID: "agent-1",
            service: .claude,
            contextTokens: tokens,
            contextWindowTokens: nil,
            project: "llm-inform-bureau",
            subagent: SubagentOrigin(
                parentSessionID: "s1",
                type: "general-purpose",
                task: "Audit the PRD",
                inheritsParentWindow: inherits
            )
        )
    }

    let payload = ClaudeStatusPayload(
        sessionID: "s1",
        project: "llm-inform-bureau",
        contextTokens: 100_000,
        contextWindowTokens: 1_000_000,
        limits: nil,
        writtenAt: Date()
    )

    suite.test("a subagent is measured against the window of the session that started it") {
        let joined = UsageReader.withWindowSizes(.value([session, subagent(inherits: true)]), from: [payload])
        guard let agent = joined.value?.first(where: { $0.isSubagent }) else {
            suite.expect(false, "expected the subagent through the join")
            return
        }
        suite.expectEqual(agent.contextWindowTokens, 1_000_000, "the window size is the session's")
        suite.expectClose(agent.windowFillPercent, 30, "and the fill is the agent's own")
        suite.expectEqual(
            joined.value?.first { !$0.isSubagent }?.contextTokens, 100_000,
            "the session is measured on its own tokens, not on its agents'"
        )
    }

    suite.test("a subagent given its own model is tokens alone, never a share of somebody else's window") {
        let joined = UsageReader.withWindowSizes(.value([session, subagent(inherits: false)]), from: [payload])
        guard let agent = joined.value?.first(where: { $0.isSubagent }) else {
            suite.expect(false, "expected the subagent through the join")
            return
        }
        suite.expect(agent.contextWindowTokens == nil, "the window size is unknown")
        suite.expect(agent.windowFillPercent == nil, "so there is no percentage")
        suite.expectEqual(agent.contextTokens, 300_000, "the tokens are still reported")

        let assessment = rules.assess(agent)
        suite.expectEqual(assessment.level, .normal, "nothing to place on the scale")
        suite.expect(assessment.levelSource == nil, "and no mark claims to have been crossed")
    }

    suite.test("a subagent of a session nobody reported a window for stays without one") {
        let joined = UsageReader.withWindowSizes(.value([session, subagent(inherits: true)]), from: [])
        suite.expect(
            joined.value?.first { $0.isSubagent }?.contextWindowTokens == nil,
            "an unknown window is not inherited as a number"
        )
    }

    // MARK: What a subagent's mark is allowed to do

    suite.test("the marks of subagents are not the service's light") {
        let quiet = rules.assess(
            SessionSnapshot(sessionID: "s1", service: .claude, contextTokens: 10_000, contextWindowTokens: 1_000_000)
        )
        let loud = rules.assess(subagent(inherits: true, tokens: 950_000).withWindow(1_000_000))
        suite.expectEqual(loud.level, .high, "the agent itself is deep into its window")
        suite.expectEqual(
            BudgetRules.serviceContextLevel(of: [quiet, loud]), .normal,
            "and the service's light is its sessions' business"
        )
        suite.expect(
            BudgetRules.serviceContextLevel(of: [loud]) == nil,
            "a service whose only reading is an agent has nothing to show"
        )
    }

    suite.test("no mark of a subagent is ever announced") {
        var dispatch = AlertDispatch()
        let quiet = subagent(inherits: true, tokens: 100_000).withWindow(1_000_000)
        let crossing = subagent(inherits: true, tokens: 950_000).withWindow(1_000_000)

        // The first pass is silent for everything, so the crossing has to happen with the app
        // already watching — which is exactly when a session would be announced.
        _ = dispatch.pending(limits: [], sessions: [rules.assess(quiet)])
        let announced = dispatch.pending(limits: [], sessions: [rules.assess(crossing)])
        suite.expectEqual(announced.count, 0, "an agent crossing every mark says nothing: \(announced.map(\.kind))")
    }
}
