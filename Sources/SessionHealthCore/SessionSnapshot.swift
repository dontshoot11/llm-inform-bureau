import Foundation

/// Where a subagent came from, and what it is allowed to borrow from there.
///
/// Claude Code starts a subagent on a context of its own and writes it to a file of its own, so
/// it is a consumer of a window in its own right rather than part of the session that started
/// it. What it does *not* have of its own is the size of that window: no file of an agent's
/// names it, and the variant of a model with the larger window is written exactly like the
/// ordinary one. So the size is inherited, and only while there is a reason to believe the
/// agent runs on the session's model — see `inheritsParentWindow`.
public struct SubagentOrigin: Equatable, Sendable {
    /// The session the agent was started from. An agent is shown nested under it and leaves
    /// the list with it: an agent on its own is a row nothing explains.
    public let parentSessionID: String

    /// The kind of agent, as its metadata names it, or `nil` when there is no metadata file.
    /// Around one agent in forty has none, and a row for it is better than a missing row.
    public let type: String?

    /// What the agent was asked to do, in the words of whoever asked.
    public let task: String?

    /// Whether the size of the session's window is this agent's size too.
    ///
    /// The metadata names a model only when one was set for the agent, which is the signal
    /// this rests on: no model named means the session's model. A named one means the window
    /// is unknown — an alias like `opus` cannot be matched against the identifier of a variant
    /// (`claude-opus-5[1m]`), and a percentage of the wrong window is worse than none.
    public let inheritsParentWindow: Bool

    public init(parentSessionID: String, type: String?, task: String?, inheritsParentWindow: Bool) {
        self.parentSessionID = parentSessionID
        self.type = type
        self.task = task
        self.inheritsParentWindow = inheritsParentWindow
    }
}

/// One reading of a coding-agent session, as it was found on disk.
///
/// Everything the budget rules need and nothing else. Where the numbers come from
/// (Claude transcripts and the statusLine wrapper, Codex rollouts) is the data layer's
/// business, not this type's.
public struct SessionSnapshot: Equatable, Sendable {
    /// Identifies the session for as long as it lives. A `/clear` starts a new session file
    /// with a new identifier, which is what makes the alert memory reset by itself.
    public let sessionID: String

    public let service: AgentService

    /// The project being worked on, as the session's working directory names it, or `nil`
    /// when the source did not say. A name, not a path: the menu has one line per session.
    public let project: String?

    /// When the session was last written to. What separates the sessions being worked on
    /// right now from the hundreds the machine has accumulated — the rule is `SessionActivity`.
    public let lastActivityAt: Date

    /// Tokens currently held in the context window.
    public let contextTokens: Int

    /// Size of the context window, or `nil` when it is unknown.
    /// Codex rollouts carry it; a Claude transcript does not, only the statusLine wrapper does.
    public let contextWindowTokens: Int?

    /// How much the context grew over the last completed turn, or `nil` when this is the
    /// first reading of the session and there is nothing to compare against.
    public let turnGrowthTokens: Int?

    /// Whether the agent owes this session an answer right now — a question was asked, or a
    /// tool was called, and nothing has come back yet.
    ///
    /// Derived, not observed: nothing on disk announces a request in flight, so this is read
    /// off the last thing written — whose entry it was, and whether it promised another. The
    /// rule belongs to whichever reader knows the shape of its own source, and it is a fact
    /// about the session rather than a decision of the view, so it is carried here beside
    /// `lastActivityAt`.
    public let isAwaitingReply: Bool

    /// Set when this reading is a subagent's rather than a session's. Everything above means
    /// the same thing either way — the difference is what it is allowed to do, which is why
    /// the rules and the panel ask this question and the reader does not answer it twice.
    public let subagent: SubagentOrigin?

    public var isSubagent: Bool { subagent != nil }

    public init(
        sessionID: String,
        service: AgentService,
        contextTokens: Int,
        contextWindowTokens: Int?,
        turnGrowthTokens: Int? = nil,
        project: String? = nil,
        lastActivityAt: Date = Date(),
        isAwaitingReply: Bool = false,
        subagent: SubagentOrigin? = nil
    ) {
        self.sessionID = sessionID
        self.service = service
        self.contextTokens = contextTokens
        self.contextWindowTokens = contextWindowTokens
        self.turnGrowthTokens = turnGrowthTokens
        self.project = project
        self.lastActivityAt = lastActivityAt
        self.isAwaitingReply = isAwaitingReply
        self.subagent = subagent
    }

    /// The same reading, told how big its window is.
    ///
    /// The one thing a Claude transcript never carries, and the one thing that arrives from
    /// somewhere else: the statusLine wrapper for a session, the session itself for a subagent.
    public func withWindow(_ tokens: Int?) -> SessionSnapshot {
        SessionSnapshot(
            sessionID: sessionID,
            service: service,
            contextTokens: contextTokens,
            contextWindowTokens: tokens,
            turnGrowthTokens: turnGrowthTokens,
            project: project,
            lastActivityAt: lastActivityAt,
            isAwaitingReply: isAwaitingReply,
            subagent: subagent
        )
    }

    /// Share of the context window in use, 0...100, or `nil` when the window size is unknown.
    ///
    /// `nil` means unknown, never zero: the interface shows absolute tokens and no percentage.
    public var windowFillPercent: Double? {
        guard let window = contextWindowTokens, window > 0 else { return nil }
        return Double(contextTokens) / Double(window) * 100
    }
}
