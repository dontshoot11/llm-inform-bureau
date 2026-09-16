import Foundation
import SwiftUI
import AgentFiles
import Phrasing
import SessionHealthCore

/// One active session as the panel shows it: what was read, what the rules made of it, and the
/// subagents running inside it.
///
/// A subagent is the same shape — it holds a context and is judged by the same marks — so it is
/// the same type, one level in. What differs is what it is allowed to do, and that is decided
/// by the rules from `snapshot.isSubagent`, not by this nesting.
struct SessionView: Identifiable, Equatable {
    let snapshot: SessionSnapshot
    let assessment: ContextAssessment
    var subagents: [SessionView] = []

    var id: String { "\(snapshot.service.rawValue):\(snapshot.sessionID)" }

    /// This reading and its subagents', which is what the service's light is decided from.
    var assessments: [ContextAssessment] { [assessment] + subagents.map(\.assessment) }
}

/// One light, and everything it can be.
///
/// Three outcomes rather than a level and a couple of flags, because they are drawn as three
/// different things and mean three different things. `unknown` never collapses into green:
/// nothing reported is not the same as nothing wrong.
enum Light: Equatable {
    /// Nothing has been reported. Claude's limits until the wrapper is connected; a service's
    /// context while nothing of its is running.
    case unknown
    /// A reading, at the level the rules put it.
    case level(BudgetLevel)
    /// A subscription window with nothing left in it. Not a worse shade of red — red says the
    /// end is close, and this says the work stops until the window resets.
    case spent
}

/// The two lights one service shows: what its subscription has cost, and what its running
/// sessions hold.
struct ServiceLights: Equatable {
    let limits: Light
    let context: Light
}

/// What the menu bar is currently showing, and what keeps it current.
///
/// Reading happens off the main actor and the published values are replaced only once a
/// reading is complete, so the panel always shows the previous numbers rather than a blank
/// while the next ones are being read.
///
/// A refresh happens when a source file changes, which is when a turn ends — that is what
/// makes a notification arrive at the moment a mark is crossed rather than within an interval.
/// The heartbeat underneath it is not a second way of noticing changes: it is for what changes
/// without anything being written, which is every age and every reset time in the panel, and a
/// session going quiet long enough to fall off the list.
@MainActor
final class UsageModel: ObservableObject {
    /// How often the panel is refreshed with nothing having changed on disk. Long enough to
    /// cost nothing, short enough that "reported 2m ago" is never a lie by much.
    static let heartbeatInterval = Duration.seconds(30)

    /// How long to let file events settle before reading. One turn writes to several files in
    /// a burst; reading once at the end of it is both cheaper and more accurate.
    static let settleDelay = Duration.milliseconds(200)

    @Published private(set) var usage: UsageReading?
    @Published private(set) var limits: [AgentService: LimitsAssessment] = [:]
    @Published private(set) var sessions: [SessionView] = []
    @Published private(set) var configProblems: [String] = []

    /// The marks currently in force, republished on every pass along with everything they were
    /// applied to. The panel reads its own explanation of the colours out of this rather than
    /// spelling the numbers out again, so an edited config cannot leave the panel describing a
    /// scale the app has stopped using.
    @Published private(set) var thresholds: ThresholdConfig = .builtIn

    /// The worst reading of all four lights, and what it was. The lights say which service and
    /// which half; this one line in the panel says which reading, because a lit dot with no
    /// explanation is a riddle.
    @Published private(set) var level: BudgetLevel = .normal
    @Published private(set) var levelReason: String?

    /// The worst reading drawn the way the bar draws it, so the line explaining a cross is
    /// marked with a cross and not with a dot of the same colour.
    @Published private(set) var levelLight: Light = .level(.normal)

    /// How far through its pulse each service is, 0 to 1, for the services pulsing right now.
    ///
    /// Only the context light pulses, and it does so for two reasons, on one channel. It blinks
    /// once through when a session's token count moves — seeing out of the corner of an eye
    /// that the numbers behind the bar have changed, without opening the panel — and it goes on
    /// blinking, beat after beat, for as long as a session is waiting on its agent. The limits
    /// light is left alone either way: a limit window creeping up is not news.
    ///
    /// One channel rather than two on purpose. A second rhythm laid over the first is a ripple
    /// in which neither is legible, and a period of 200ms against one of 400 is not something
    /// an eye catches sideways, which is the only way this is ever looked at. What tells the
    /// two apart is how long they last: three blinks and steady again is "the reading moved",
    /// blinking that does not stop is "it is still working".
    ///
    /// **Waiting is derived, not observed.** Measured: while a turn is being worked on, neither
    /// the statusLine payload nor the transcript is written — both move only when a step lands.
    /// So the blink rests on what the last thing written leaves owed
    /// (`SessionSnapshot.isAwaitingReply`), which is the strongest true thing this app can say.
    @Published private(set) var pulse: [AgentService: Double] = [:]

    /// The same pulse, per session, for the panel — where there is room to say which of three
    /// Claude sessions moved. The bar has one light per service and can only blink for "one of
    /// them did"; a row of its own can be honest about which.
    @Published private(set) var sessionPulse: [String: Double] = [:]

    private let notifier: Notifier
    private var dispatch = AlertDispatch()
    private var watcher: SourceWatcher?
    private var heartbeat: Task<Void, Never>?
    private var settling: Task<Void, Never>?

    /// Guards against two readings at once: a burst of file events must not start a second
    /// read over the first, and the second must not be dropped either.
    private var isReading = false
    private var readAgain = false

    /// What each service's sessions were holding, as of the last pass: session id to tokens.
    /// A pulse is started when one of these numbers moves, which is the same number the panel
    /// shows and the same one the agent's own status line shows.
    ///
    /// Deliberately the reading and not the file: a file can be rewritten with what was already
    /// in it — the wrapper does exactly that when a turn ends without the count moving — and a
    /// light that flashed for that would be announcing nothing.
    private var lastHeld: [AgentService: [String: SessionNumbers]] = [:]
    private var pulsing: Task<Void, Never>?

    /// Who is waiting on an agent as of the last pass, by service for the bar and by session
    /// for the panel. What keeps a blink going round instead of running out — and, being
    /// replaced whole on every pass, what stops it the moment the answer lands.
    private var waitingServices: Set<AgentService> = []
    private var waitingSessions: Set<String> = []

    init(paths: [URL] = SourceWatcher.defaultPaths, notifier: Notifier = Notifier()) {
        self.notifier = notifier

        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: UsageModel.heartbeatInterval)
            }
        }

        let watcher = SourceWatcher(paths: paths) { [weak self] in
            Task { @MainActor in self?.sourcesChanged() }
        }
        watcher.start()
        self.watcher = watcher
    }

    deinit {
        heartbeat?.cancel()
        settling?.cancel()
        pulsing?.cancel()
        watcher?.stop()
    }

    /// A file under one of the watched trees changed. Every turn ends in several such events,
    /// so they are collected before anything is read.
    private func sourcesChanged() {
        settling?.cancel()
        settling = Task { [weak self] in
            try? await Task.sleep(for: UsageModel.settleDelay)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// What one service shows in the bar, and next to its name in the panel.
    ///
    /// The context light is the worst of that service's running sessions, because the bar has
    /// room for a verdict and not for a list — which session it was is a line in the panel.
    func lights(of service: AgentService) -> ServiceLights {
        let readings = sessions
            .filter { $0.snapshot.service == service }
            .flatMap(\.assessments)
        let limits = limits[service]
        // Which of those readings the light is entitled to — a session with no window size to
        // place on the scale, a subagent whose mark is silent by design — is the rule's
        // decision and not this view's.
        return ServiceLights(
            limits: limits.map { $0.isExhausted ? .spent : .level($0.level) } ?? .unknown,
            context: BudgetRules.serviceContextLevel(of: readings).map(Light.level) ?? .unknown
        )
    }

    /// How far through its pulse this service is, or nil when it is not pulsing.
    func pulse(of service: AgentService) -> Double? { pulse[service] }

    /// How far through its pulse this session is, or nil when it is not pulsing.
    func pulse(ofSession sessionID: String) -> Double? { sessionPulse[sessionID] }

    func refresh() async {
        // A read already running will see everything this one would have; asking it to go
        // round once more is how the last event of a burst is not lost.
        guard !isReading else {
            readAgain = true
            return
        }
        isReading = true
        defer {
            isReading = false
            if readAgain {
                readAgain = false
                Task { await refresh() }
            }
        }

        // Re-read on every pass, so editing the config file changes behaviour without a restart.
        let load = ThresholdConfigLoader.load()
        let rules = BudgetRules(config: load.config)
        let reading = await Self.read(config: load.config)

        var limits: [AgentService: LimitsAssessment] = [:]
        for service in AgentService.allCases {
            guard let snapshot = reading.limits(of: service).value else { continue }
            limits[service] = rules.assess(snapshot)
        }

        let sessions = Self.nested(
            AgentService.allCases
                .flatMap { reading.sessions(of: $0).value ?? [] }
                .map { SessionView(snapshot: $0, assessment: rules.assess($0)) }
        )

        let worst = Self.worst(of: limits, and: sessions, config: load.config)

        self.usage = reading
        self.limits = limits
        self.sessions = sessions
        self.configProblems = load.problems
        self.thresholds = load.config
        self.level = worst.level
        self.levelReason = worst.reason
        self.levelLight = worst.isSpent ? .spent : .level(worst.level)

        updateWaiting(for: sessions)
        startPulses(for: sessions)

        // Announced after the panel is current, so that opening the menu from a notification
        // shows the reading the notification is about.
        // Subagents go in along with their sessions: whether a reading is worth interrupting
        // somebody for is the dispatcher's decision, and handing it a filtered list would move
        // that decision here, where no test can see it.
        let fresh = dispatch.pending(
            limits: AgentService.allCases.compactMap { limits[$0] },
            sessions: sessions.flatMap(\.assessments)
        )
        notifier.deliver(fresh.map { AlertPhrasing.text(for: $0, config: load.config) })
    }

    /// How long one pulse lasts, and how many frames it is drawn in.
    ///
    /// Short and few on purpose. The animation exists only while a pulse does — there is no
    /// timer running the rest of the time, which is the whole reason this is affordable in a
    /// menu bar app that otherwise wakes only when a file changes.
    /// Three blinks, six frames: the light goes out and comes back three times, 200ms a state.
    /// One flash is easy to miss if you were looking at the other half of the screen, which is
    /// the whole situation this exists for.
    ///
    /// Six frames and not more. The frames are drawn by SwiftUI redrawing the menu bar label,
    /// and a state that lasts 200ms survives that; a fade drawn over a dozen frames did not
    /// show up at all — see `BarLights.blinkedOut`.
    static let pulseDuration = Duration.milliseconds(1200)
    static let pulseFrames = 6


    /// Keeps the light of every session waiting on its agent blinking, and lets the rest run out.
    ///
    /// A subagent counts as a session of its own here, the way it does everywhere else: it has
    /// a row in the panel, and a row that is working says so for itself. Its service blinks for
    /// the same reason the bar blinks for any one of its sessions — the bar has one light and
    /// can only say "one of these".
    ///
    /// Nothing is stopped here. A light that has stopped waiting simply finishes the blink it
    /// is in and drops out, which is one beat at most and leaves it lit rather than dark: a
    /// blink cut off mid-beat is read as the light going out for good.
    private func updateWaiting(for sessions: [SessionView]) {
        let waiting = sessions.flatMap { [$0] + $0.subagents }.filter(\.snapshot.isAwaitingReply)
        waitingServices = Set(waiting.map(\.snapshot.service))
        waitingSessions = Set(waiting.map(\.snapshot.sessionID))
        guard !waiting.isEmpty else { return }

        for service in waitingServices where pulse[service] == nil { pulse[service] = 0 }
        for sessionID in waitingSessions where sessionPulse[sessionID] == nil { sessionPulse[sessionID] = 0 }
        animatePulses()
    }

    /// Starts a pulse for every service whose sessions are holding different numbers than they
    /// were on the last pass — a session's count moving, one appearing, one dropping off.
    private func startPulses(for sessions: [SessionView]) {
        var held: [AgentService: [String: SessionNumbers]] = [:]
        for view in sessions {
            held[view.snapshot.service, default: [:]][view.snapshot.sessionID] = SessionNumbers(
                held: view.snapshot.contextTokens,
                lastRequest: view.snapshot.turnGrowthTokens
            )
        }
        let previous = lastHeld
        lastHeld = held
        // Nothing flashes on the first reading after launch: everything is new then, and a bar
        // that flashes at startup says "this just changed" about a machine that has been idle
        // for hours.
        guard !previous.isEmpty else { return }

        let moved = held.filter { $0.value != previous[$0.key] }
        guard !moved.isEmpty else { return }
        for (service, numbers) in moved {
            pulse[service] = 0
            let before = previous[service] ?? [:]
            for (sessionID, current) in numbers where current != before[sessionID] {
                sessionPulse[sessionID] = 0
            }
        }
        animatePulses()
    }

    /// Advances every running pulse frame by frame, and stops the moment none is left.
    private func animatePulses() {
        guard pulsing == nil else { return }
        let frame = Self.pulseDuration / Self.pulseFrames
        pulsing = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: frame)
                guard let self, !Task.isCancelled else { return }
                var next: [AgentService: Double] = [:]
                for (service, phase) in self.pulse {
                    next[service] = Self.advance(phase, looping: self.waitingServices.contains(service))
                }
                var nextSessions: [String: Double] = [:]
                for (sessionID, phase) in self.sessionPulse {
                    nextSessions[sessionID] = Self.advance(
                        phase,
                        looping: self.waitingSessions.contains(sessionID)
                    )
                }
                // Assigning `nil` to a key removes it, which is how a blink that has run out
                // leaves the dictionary and stops being drawn.
                self.pulse = next
                self.sessionPulse = nextSessions
                if next.isEmpty, nextSessions.isEmpty {
                    self.pulsing = nil
                    return
                }
            }
        }
    }

    /// The next frame of a blink, or `nil` once it has run out — which a light that is still
    /// waiting never does: it starts the same blink over rather than stopping.
    ///
    /// Counted in frames rather than added up in fractions. A sixth added to itself six times
    /// does not make one, and a beat that comes out a frame long every so often is exactly the
    /// unevenness a blink that never stops would put on show.
    private static func advance(_ phase: Double, looping: Bool) -> Double? {
        let next = Int((phase * Double(pulseFrames)).rounded()) + 1
        if next < pulseFrames { return Double(next) / Double(pulseFrames) }
        return looping ? 0 : nil
    }

    /// Sessions with their subagents underneath them, worst session first.
    ///
    /// An agent belongs under the session that started it, and the reader has already dropped
    /// the ones whose session is no longer listed — so anything still claiming a parent that
    /// is not here would be a row with nothing above it, and is left out.
    private static func nested(_ views: [SessionView]) -> [SessionView] {
        let subagents = Dictionary(grouping: views.filter(\.snapshot.isSubagent)) {
            $0.snapshot.subagent?.parentSessionID ?? ""
        }
        return views
            .filter { !$0.snapshot.isSubagent }
            .map { session in
                SessionView(
                    snapshot: session.snapshot,
                    assessment: session.assessment,
                    subagents: (subagents[session.snapshot.sessionID] ?? [])
                        .sorted { $0.snapshot.lastActivityAt > $1.snapshot.lastActivityAt }
                )
            }
            .sorted { $0.assessment.level > $1.assessment.level }
    }

    /// The worst of everything being watched, and the one line that explains it.
    ///
    /// Limits and context are compared on the same scale on purpose: what stops the work is
    /// whichever runs out first, and one sentence is all the panel spends on saying which.
    private static func worst(
        of limits: [AgentService: LimitsAssessment],
        and sessions: [SessionView],
        config: ThresholdConfig
    ) -> (level: BudgetLevel, reason: String?, isSpent: Bool) {
        // A spent window outranks everything, including another reading at the same level: one
        // of them says the work may get harder, the other that it has stopped.
        var candidates: [(level: BudgetLevel, reason: String, isSpent: Bool)] = []
        for (service, assessment) in limits {
            if let spent = assessment.spentWindow {
                candidates.append((
                    assessment.level,
                    Wording.spent(service, window: spent.kind, resetsAt: spent.resetsAt),
                    true
                ))
                continue
            }
            guard let source = assessment.levelSource else { continue }
            candidates.append((assessment.level, Wording.reason(for: source, service: service, config: config), false))
        }
        for session in sessions {
            guard let source = session.assessment.levelSource else { continue }
            let reason = Wording.reason(for: source, service: session.snapshot.service, config: config)
            let project = session.snapshot.project.map { " (\($0))" } ?? ""
            candidates.append((session.assessment.level, reason + project, false))
        }
        let worst = candidates.max {
            ($0.level, $0.isSpent ? 1 : 0) < ($1.level, $1.isSpent ? 1 : 0)
        }
        guard let worst else { return (.normal, nil, false) }
        return (worst.level, worst.reason, worst.isSpent)
    }

    /// `nonisolated async` on purpose: it runs off the main actor, so a slow disk cannot make
    /// the panel stutter.
    private nonisolated static func read(config: ThresholdConfig) async -> UsageReading {
        UsageReader().read(config: config)
    }
}




/// The two numbers the panel shows for a session: what it holds, and what the last request
/// added. Both are compared, because the pulse should fire whenever either of the numbers a
/// person is looking at has moved — they come from the same reading, and either one changing
/// means the reading did.
struct SessionNumbers: Equatable {
    let held: Int
    let lastRequest: Int?
}
