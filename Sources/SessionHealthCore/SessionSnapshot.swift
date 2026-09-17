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

/// Who is being waited on in this session, and — for the two cases where it matters — since
/// when.
///
/// Four outcomes rather than a yes and a no. Three of them are about the agent: an answer that
/// has not come in ten seconds and one that has not come in an hour are different things to a
/// person glancing at the bar, and the app cannot tell the second from a session that died.
/// What it can say is how long the silence has run, and that is the whole difference between
/// `.waiting` and `.stalled`.
///
/// The fourth is the other direction entirely: the agent has asked for something and is
/// standing still until the person answers. It is one question — "who are we waiting on" —
/// with four answers, so it is one value and not a state beside a flag: two fields would
/// leave every reader of them, the bar and the panel and the rules, to put them back together
/// on its own.
/// What the agent stopped for, when it has stopped and is waiting on the person.
///
/// Two things bring a session to a halt with the next move belonging to the person, and the
/// bar draws them the same — the pause sign says "you" and nothing finer. The difference is
/// for the notification, which has a sentence to spend and owes the person the reason they are
/// being interrupted: a question is answered by reading it, a permission prompt by deciding.
///
/// Measured on live sessions of Claude Code 2.1.274 (see the task's research.md): a question
/// puts the session record in `waiting` with `waitingFor: "input needed"`, a permission prompt
/// in `waiting` with `waitingFor: "permission prompt"`. Neither carries what is being asked
/// about — the question's own words come from the transcript, and the permission prompt's
/// words are nowhere on disk at all.
public enum Asking: Equatable, Sendable {
    /// The agent put a question to the person. Its words, when the transcript carries them,
    /// travel separately in `SessionSnapshot.request`.
    case question
    /// The agent wants to use a tool and is held until the person allows or refuses it.
    case permission
    /// The record says the person is being waited on and does not say what for — an unfamiliar
    /// `waitingFor`, or none at all. Read as a request, worded as the release before this one
    /// worded every request: the app never invents a reason it was not told.
    case unnamed
}

public enum ReplyWait: Equatable, Sendable {
    /// Nothing is owed: the turn ended, and nobody is being waited on.
    case none
    /// An answer is owed by the agent and the silence is still short enough to believe in.
    /// The blinking light.
    case waiting
    /// An answer is owed by the agent and has been owed past the fuse
    /// (`sessions.abandoned_wait_after_minutes`). Either the agent is thinking very hard or
    /// the session is gone; nothing on disk separates the two, so the app says the one thing
    /// it knows — there has been no answer for a long time — and draws the sign for it.
    case stalled
    /// The agent is asking the person for something — a question, or permission to run
    /// something — and nothing moves until they answer. The pause sign.
    ///
    /// Carries the moment the asking started, which the other two cases have no use for and
    /// this one does: the fuse above never applies to it — a request does not go stale, the
    /// person simply has not come back yet — and how long it has stood is what a notification
    /// waits on. It carries what was asked for beside it, because the two arrive from the same
    /// file in the same reading and only the notification tells them apart.
    case asking(since: Date, for: Asking)

    /// Whether the *agent* owes an answer, however long it has been owed. Being asked
    /// something is not that: the next move is the person's.
    public var isOwed: Bool { self == .waiting || self == .stalled }

    /// When the agent started asking the person for something, or `nil` when it is not asking.
    public var askingSince: Date? {
        guard case .asking(let since, _) = self else { return nil }
        return since
    }

    /// What it is asking for, or `nil` when it is not asking.
    public var askingFor: Asking? {
        guard case .asking(_, let what) = self else { return nil }
        return what
    }

    /// Whether the person, rather than the agent, is the one being waited on.
    public var isAsking: Bool { askingSince != nil }
}

/// One reading of a coding-agent session, as it was found on disk.
///
/// Everything the budget rules need and nothing else. Where the numbers come from
/// (Claude transcripts and the status line, Codex rollouts) is the data layer's
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

    /// The model that answered last, as the source names it — `claude-opus-5`,
    /// `gpt-5.6-sol` — or `nil` when it did not say.
    ///
    /// The identifier and not a tidied-up name: both services write the identifier and neither
    /// writes anything else that every session has, so a prettier name would have to be
    /// invented here from a table that goes stale the week a model ships. It is shown as what
    /// it is, in the font the panel keeps for things you would type.
    public let model: String?

    /// Tokens currently held in the context window.
    public let contextTokens: Int

    /// Size of the context window, or `nil` when it is unknown.
    /// Codex rollouts carry it; a Claude transcript does not, only the status line does.
    public let contextWindowTokens: Int?

    /// How much the context grew over the last completed turn, or `nil` when this is the
    /// first reading of the session and there is nothing to compare against.
    public let turnGrowthTokens: Int?

    /// Who this session is waiting on right now — its agent, or the person at the keyboard.
    ///
    /// Mostly derived rather than observed: nothing on disk announces a request in flight, so
    /// the agent's side is read off the last thing written — whose entry it was, and whether it
    /// promised another. The one case that *is* observed is the other side, where Claude Code
    /// writes down that it is waiting on the person (`ClaudeSessionRecordStore`).
    ///
    /// Either way the rule belongs to whichever reader knows the shape of its own source, and
    /// it is a fact about the session rather than a decision of the view, so it is carried here
    /// beside `lastActivityAt`.
    public let replyWait: ReplyWait

    /// What the agent last asked the person for, in its own words, or `nil` when nothing in
    /// the transcript is waiting on an answer from them.
    ///
    /// Carried beside `replyWait` rather than inside its `.asking` case, because the two come
    /// from two different files and the transcript is read first: the transcript knows what
    /// was asked and cannot tell a question from a running tool, and the session record tells
    /// them apart and does not carry the question. Whoever reads both puts them together.
    ///
    /// The question as it was written, whole. Shortening it is the interface's business, and
    /// the notification is the only thing that has to.
    public let request: String?

    /// The process this session is running in, when one was found alive this pass, and `nil`
    /// otherwise.
    ///
    /// The whole of what the panel needs to take a person to their session: from a pid the
    /// system knows the terminal it sits in and the application that started it. A reading
    /// with none — a session whose CLI writes no record, a Codex session, a subagent, a
    /// process that has since exited — is a row that promises nothing, and that is the point
    /// of it being optional rather than a number that might be stale.
    ///
    /// Checked, not copied: whoever sets this has confirmed against the running process that
    /// the pid is still the one the record was written about (`SessionProcess.isTheOne`),
    /// because a pid is a number the system hands out again.
    public let processID: Int32?

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
        model: String? = nil,
        project: String? = nil,
        lastActivityAt: Date = Date(),
        replyWait: ReplyWait = .none,
        request: String? = nil,
        processID: Int32? = nil,
        subagent: SubagentOrigin? = nil
    ) {
        self.sessionID = sessionID
        self.service = service
        self.contextTokens = contextTokens
        self.contextWindowTokens = contextWindowTokens
        self.turnGrowthTokens = turnGrowthTokens
        self.model = model
        self.project = project
        self.lastActivityAt = lastActivityAt
        self.replyWait = replyWait
        self.request = request
        self.processID = processID
        self.subagent = subagent
    }

    /// The same reading, told how big its window is.
    ///
    /// The one thing a Claude transcript never carries, and the one thing that arrives from
    /// somewhere else: the status line for a session, the session itself for a subagent.
    public func withWindow(_ tokens: Int?) -> SessionSnapshot {
        SessionSnapshot(
            sessionID: sessionID,
            service: service,
            contextTokens: contextTokens,
            contextWindowTokens: tokens,
            turnGrowthTokens: turnGrowthTokens,
            model: model,
            project: project,
            lastActivityAt: lastActivityAt,
            replyWait: replyWait,
            request: request,
            processID: processID,
            subagent: subagent
        )
    }

    /// The same reading, told what the record of its running process knows: since when the
    /// agent has been asking the person for something, and which process it is running in.
    ///
    /// Told rather than read, because these come from a different file than everything above.
    /// The transcript says what the session holds and whether the agent owes it an answer;
    /// only the record says the agent has stopped and is waiting on the person, and that
    /// answer overrides the transcript's — a question is written there as a tool call like any
    /// other, which is exactly what "the agent is working" looks like. The process is the same
    /// story: nothing a transcript contains leads to the window a person is sitting in front
    /// of.
    ///
    /// The moment and the process are optional and independent. A record may say a session is
    /// asking while its process has already been checked and found gone, and a live process
    /// says nothing about anybody waiting. What is being asked for is read only when there is
    /// a moment to go with it — nothing is asked for at no time.
    public func withRecord(asking since: Date?, for what: Asking, process: Int32?) -> SessionSnapshot {
        SessionSnapshot(
            sessionID: sessionID,
            service: service,
            contextTokens: contextTokens,
            contextWindowTokens: contextWindowTokens,
            turnGrowthTokens: turnGrowthTokens,
            model: model,
            project: project,
            lastActivityAt: lastActivityAt,
            replyWait: since.map { .asking(since: $0, for: what) } ?? replyWait,
            request: request,
            processID: process,
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
