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
    /// Nothing has been reported. Claude's limits until the status line slot is connected;
    /// a service's context while nothing of its is running.
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
/// without anything being written, which is every age and every reset time in the panel, a
/// session going quiet long enough to fall off the list, and a question that has now gone
/// unanswered for longer than `sessions.attention_notice_after_minutes`. That last one is the
/// heartbeat's alone — nothing is written to any of these files while the person is away from
/// the keyboard — so that notification arrives up to a heartbeat after the mark instead of on
/// it, which is half a minute onto a wait already minutes long.
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

    /// Whose Claude Code's status line slot is. What decides whether the panel offers to take
    /// it, and the only thing that decides whether limits can arrive at all.
    @Published private(set) var slot: StatusLineSlotState = .free

    /// The edit to `settings.json` that has been shown and not yet answered. Nothing is
    /// written while this is anything but `nil`, and nothing is written without it having been
    /// this first.
    @Published private(set) var pendingChange: StatusLineChange?

    /// Why the last write did not happen, in words the panel can show. Cleared by the next
    /// attempt — a complaint about a file somebody has since fixed is worse than none.
    @Published private(set) var slotProblem: Phrase?

    /// Which permission the last click on a session turned out to need, and `nil` while none
    /// has.
    ///
    /// One value for the panel and not one per row: the answer it is about belongs to the
    /// machine, not to a session — a system that has not been told this app may look through
    /// windows will say so about every session alike. Set only by a click, so nothing is ever
    /// said about a permission until somebody has actually wanted it.
    @Published private(set) var missingPermission: TerminalRaise.Permission?

    /// Whether the panel's limits half is opened out.
    ///
    /// Folded by default, and kept here rather than in the view so that it survives the panel
    /// being closed and opened again — the panel's own state does not. It does not survive a
    /// relaunch, and is not meant to: this is which half somebody is reading today, not a
    /// setting, and the app keeps no settings it was not asked to keep.
    @Published var limitsExpanded = false

    /// The marks currently in force, republished on every pass along with everything they were
    /// applied to. The panel reads its own explanation of the colours out of this rather than
    /// spelling the numbers out again, so an edited config cannot leave the panel describing a
    /// scale the app has stopped using.
    @Published private(set) var thresholds: ThresholdConfig = .builtIn

    /// The worst reading of all four lights, and what it was. The lights say which service and
    /// which half; this one line in the panel says which reading, because a lit dot with no
    /// explanation is a riddle.
    @Published private(set) var level: BudgetLevel = .normal
    @Published private(set) var levelReason: Phrase?

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
    /// Which is why they never run at once: while a light is waiting, its flash is suppressed
    /// (`startPulses`). One light cannot carry both, and the wait is the one that would lose —
    /// a flash restarting the beat every time the numbers move turns "still working" into
    /// series of three with gaps between them, which reads as a light dithering rather than as
    /// a process running.
    ///
    /// **Waiting is derived, not observed.** Measured: while a turn is being worked on, neither
    /// the statusLine payload nor the transcript is written — both move only when a step lands.
    /// So the blink rests on what the last thing written leaves owed
    /// (`SessionSnapshot.replyWait`), which is the strongest true thing this app can say.
    ///
    /// And it rests on that only for as long as the silence is short enough to believe in. Past
    /// the fuse the blink stops and the light is drawn as a sign instead — `stalledServices`.
    @Published private(set) var pulse: [AgentService: Double] = [:]

    /// The same pulse, per session, for the panel — where there is room to say which of three
    /// Claude sessions moved. The bar has one light per service and can only blink for "one of
    /// them did"; a row of its own can be honest about which.
    @Published private(set) var sessionPulse: [String: Double] = [:]

    /// Whose wait has gone on past the fuse, and who is being asked something, by service for
    /// the bar and by session for the panel — the lights drawn as a sign instead of a dot.
    ///
    /// Published rather than kept beside the private sets below, because unlike a blink these
    /// change nothing else: a sign starts and ends without a frame being drawn, and a view that
    /// was not told would go on showing the dot until something else moved.
    ///
    /// A service the bar would have to say two things about says the one that asks most of the
    /// person, and the order is `sign(of:)`. `stalledServices` leaves out any service that also
    /// has a session blinking or asking: a stall means "nothing has come back for ten minutes",
    /// and next to "something is running right now" or "this one wants you", it is the fact
    /// that can wait. The panel, which has a row per session, shows all of them without having
    /// to choose.
    @Published private(set) var stalledServices: Set<AgentService> = []
    @Published private(set) var stalledSessions: Set<String> = []
    @Published private(set) var askingServices: Set<AgentService> = []
    @Published private(set) var askingSessions: Set<String> = []

    /// One reader for the life of the app, not one per pass.
    ///
    /// It is what remembers which files have already been read, and that memory is the whole
    /// of why a burst of events from one transcript no longer costs a full re-read of every
    /// other one. A reader made afresh inside `refresh` — which is how this used to work —
    /// starts every pass knowing nothing.
    ///
    /// Injectable for the same reason `paths` is: a copy of the app can then be pointed at a
    /// controlled set of files instead of at the real home, which is what the measuring rig in
    /// `TODO/refresh-cost/measure/` needs. `nonisolated` because the read itself runs off the
    /// main actor.
    private nonisolated let reader: UsageReader

    private let notifier: Notifier
    private let statusLine: StatusLineSlot

    /// Which channel the notifications have gone out over, or `nil` while none has been sent.
    /// The checkup asks, because it is the only thing about notifications that is knowable
    /// without sending one.
    var notificationChannel: NotificationChannel? { notifier.channel }

    private let raiser = TerminalRaiser()
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
    /// in it — the status line does exactly that when a turn ends without the count moving —
    /// and a light that flashed for that would be announcing nothing.
    private var lastHeld: [AgentService: [String: SessionNumbers]] = [:]
    private var pulsing: Task<Void, Never>?

    /// Who is waiting on an agent as of the last pass, by service for the bar and by session
    /// for the panel. What keeps a blink going round instead of running out — and, being
    /// replaced whole on every pass, what stops it the moment the answer lands.
    private var waitingServices: Set<AgentService> = []
    private var waitingSessions: Set<String> = []

    init(
        paths: [URL] = SourceWatcher.defaultPaths,
        reader: UsageReader = UsageReader(),
        notifier: Notifier = Notifier(),
        statusLine: StatusLineSlot = StatusLineSlot()
    ) {
        self.reader = reader
        self.notifier = notifier
        self.statusLine = statusLine

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
    ///
    /// A light wearing a sign never pulses. Blinking is drawn by leaving the light out for a
    /// frame, so a sign that blinked would be a sign going missing and coming back — and the
    /// two signals are not equals: a blink says something is happening, a sign says who is
    /// being waited on, and that is the one a glance is for.
    func pulse(of service: AgentService) -> Double? {
        sign(of: service) == nil ? pulse[service] : nil
    }

    /// How far through its pulse this session is, or nil when it is not pulsing.
    func pulse(ofSession sessionID: String) -> Double? {
        sign(ofSession: sessionID) == nil ? sessionPulse[sessionID] : nil
    }

    /// What this service's light is drawn as, or nil for the dot itself.
    ///
    /// Asking wins over a stall, because it is the one of the two the person can do something
    /// about: a service with one session asking and another long silent says the request.
    func sign(of service: AgentService) -> LightSign? {
        if askingServices.contains(service) { return .asking }
        if stalledServices.contains(service) { return .stalled }
        return nil
    }

    /// What this session's own light is drawn as. A session is only ever in one of these
    /// states, so the order here settles nothing — it is the same question asked of a row.
    func sign(ofSession sessionID: String) -> LightSign? {
        if askingSessions.contains(sessionID) { return .asking }
        if stalledSessions.contains(sessionID) { return .stalled }
        return nil
    }

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
        let reading = await Self.read(with: reader, config: load.config)
        let slot = await Self.readSlot(statusLine)

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
        self.slot = slot
        self.limits = limits
        self.sessions = sessions
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
    /// can only say "one of these". What a subagent never gets is a sign: an agent asks nothing
    /// of the person, and a stall inside one ends when the agent does.
    ///
    /// Nothing is stopped here. A light that has stopped waiting simply finishes the blink it
    /// is in and drops out, which is one beat at most and leaves it lit rather than dark: a
    /// blink cut off mid-beat is read as the light going out for good.
    private func updateWaiting(for sessions: [SessionView]) {
        let rows = sessions.flatMap { [$0] + $0.subagents }.map(\.snapshot)
        let waiting = rows.filter { $0.replyWait == .waiting }
        let stalled = rows.filter { $0.replyWait == .stalled }
        let asking = rows.filter { $0.replyWait.isAsking }
        waitingServices = Set(waiting.map(\.service))
        waitingSessions = Set(waiting.map(\.sessionID))
        // Neither a stall nor a request blinks: both are drawn as a sign, and nothing here
        // keeps a frame running for them — which is what leaves an app full of them as idle as
        // one with nothing at all.
        askingServices = Set(asking.map(\.service))
        askingSessions = Set(asking.map(\.sessionID))
        stalledServices = Set(stalled.map(\.service))
            .subtracting(waitingServices)
            .subtracting(askingServices)
        stalledSessions = Set(stalled.map(\.sessionID))
        guard !waiting.isEmpty else { return }

        for service in waitingServices where pulse[service] == nil { pulse[service] = 0 }
        for sessionID in waitingSessions where sessionPulse[sessionID] == nil { sessionPulse[sessionID] = 0 }
        animatePulses()
    }

    /// Starts a pulse for every service whose sessions are holding different numbers than they
    /// were on the last pass — a session's count moving, one appearing, one dropping off.
    ///
    /// A light already blinking its wait is left out. The two signals share one light on
    /// purpose, and while the wait is running the flash has nothing left to say: a blink that
    /// does not stop already means "something is happening here". Firing it anyway would be
    /// worse than redundant — the numbers move several times a turn, measured on this machine
    /// at anything from a tenth of a second to three quarters of a minute apart, and each one
    /// would restart the beat and cut the wait into series of three. Outside a wait the flash
    /// is exactly what it was.
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

        var flashed = false
        for (service, numbers) in moved {
            if !waitingServices.contains(service) {
                pulse[service] = 0
                flashed = true
            }
            let before = previous[service] ?? [:]
            for (sessionID, current) in numbers
            where current != before[sessionID] && !waitingSessions.contains(sessionID) {
                sessionPulse[sessionID] = 0
                flashed = true
            }
        }
        guard flashed else { return }
        animatePulses()
    }

    /// Advances every running pulse frame by frame, and stops the moment none is left.
    ///
    /// Frames are placed on a fixed grid rather than slept through one length at a time. A
    /// sleep lasts *at least* what it was asked for, and the work after it takes its own time
    /// on top; beat after beat that adds up, and a blink that has to look the same at the end
    /// of a minute-long wait as it did at its start cannot afford to drift. On the grid a late
    /// frame is late once and the next one lands where it always would. `tolerance: .zero`
    /// is part of the same thing: left to itself the system is free to coalesce a wakeup with
    /// whatever else it is doing, and a frame stretched to suit the scheduler is exactly the
    /// unevenness this is here to avoid.
    ///
    /// After a real stall — a sleeping machine, a long freeze — the grid is picked up from now
    /// rather than caught up to, because a burst of frames drawn back to back is a stutter and
    /// not a blink.
    private func animatePulses() {
        guard pulsing == nil else { return }
        let frame = Self.pulseDuration / Self.pulseFrames
        pulsing = Task { [weak self] in
            var deadline = ContinuousClock.now
            while !Task.isCancelled {
                deadline = max(deadline, ContinuousClock.now).advanced(by: frame)
                try? await Task.sleep(until: deadline, tolerance: .zero, clock: .continuous)
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
    ) -> (level: BudgetLevel, reason: Phrase?, isSpent: Bool) {
        // A spent window outranks everything, including another reading at the same level: one
        // of them says the work may get harder, the other that it has stopped.
        var candidates: [(level: BudgetLevel, reason: Phrase, isSpent: Bool)] = []
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
            // The project is a folder name, so it is added to both sides as it is: it is what
            // the row above it is called, and a translated one would point at nothing.
            let project = session.snapshot.project.map { " (\($0))" } ?? ""
            candidates.append((session.assessment.level, reason.mapped { $0 + project }, false))
        }
        let worst = candidates.max {
            ($0.level, $0.isSpent ? 1 : 0) < ($1.level, $1.isSpent ? 1 : 0)
        }
        guard let worst else { return (.normal, nil, false) }
        return (worst.level, worst.reason, worst.isSpent)
    }

    /// `nonisolated async` on purpose: it runs off the main actor, so a slow disk cannot make
    /// the panel stutter.
    private nonisolated static func read(
        with reader: UsageReader,
        config: ThresholdConfig
    ) async -> UsageReading {
        reader.read(config: config)
    }

    /// Off the main actor for the same reason, and re-read on every pass rather than once at
    /// launch: the slot is a file somebody can edit while this app is running, and a panel
    /// offering to connect something that is already connected is the app talking about a
    /// machine that no longer exists.
    private nonisolated static func readSlot(_ slot: StatusLineSlot) async -> StatusLineSlotState {
        slot.state()
    }

    // MARK: Taking the slot, and giving it back

    /// Works out what the button would change and puts it in front of the user. Writes nothing.
    ///
    /// A change that comes back `nil` means the file already looks the way the button would
    /// leave it — somebody edited it by hand, or another copy of this app got there first — so
    /// the answer is to re-read rather than to offer anything.
    func propose(_ kind: StatusLineChange.Kind) {
        slotProblem = nil
        pendingChange = statusLine.change(for: kind)
        if pendingChange == nil {
            Task { await refresh() }
        }
    }

    /// The other answer. Nothing has been written at this point, so there is nothing to undo.
    func cancelChange() {
        pendingChange = nil
    }

    /// Carries out the change that was shown, and says so if it did not happen.
    func applyChange() {
        guard let change = pendingChange else { return }
        pendingChange = nil
        Task { slotProblem = await write(change) }
    }

    /// What a change would be, without putting it in front of anybody.
    ///
    /// The settings window asks this: the way back out of the slot lives there now, and it
    /// shows the change in its own row rather than through the panel's question — a preview
    /// published here would appear under the Claude limits, behind the window somebody is
    /// reading it in.
    func plannedChange(_ kind: StatusLineChange.Kind) -> StatusLineChange? {
        statusLine.change(for: kind)
    }

    /// Writes a change that was shown first, and answers with what went wrong, or `nil`.
    ///
    /// The one way this app edits `settings.json`, wherever the question was asked: the panel
    /// keeps what comes back in `slotProblem`, and the window shows it beside the row it was
    /// pressed in. Whoever asked reads the file again afterwards, because both of them show
    /// what is in it rather than what this method believes it did.
    func write(_ change: StatusLineChange) async -> Phrase? {
        var problem: Phrase?
        do {
            try statusLine.apply(change)
        } catch let failure as ClaudeSettings.Failure {
            problem = Self.explain(failure)
        } catch {
            // The system's own words, which come in whatever language it gives them.
            problem = SlotPhrasing.failed(.name(error.localizedDescription))
        }
        await refresh()
        return problem
    }

    private static func explain(_ failure: ClaudeSettings.Failure) -> Phrase {
        switch failure {
        case .unreadable(let path): SlotPhrasing.unreadable(path)
        case .notWritten(let reason): SlotPhrasing.failed(reason)
        }
    }

    // MARK: Going to the session

    /// Brings up the window a session is running in — the end of the road every reading in
    /// this panel is on.
    ///
    /// Nothing happens for a session with no live process behind it: `processID` is `nil`
    /// exactly then, the row offers no click in the first place, and this is the second half
    /// of that promise rather than a repetition of it.
    func raise(_ snapshot: SessionSnapshot) {
        guard let pid = snapshot.processID else { return }
        Task { [weak self] in
            guard let outcome = await self?.raiser.raise(
                processID: pid,
                project: snapshot.project
            ) else { return }
            // Only a missing permission leaves anything on screen. Every other outcome says
            // nothing: what the person asked for is now in front of them, and a panel
            // commenting on that would be talking about itself.
            if case .appWithout(let permission) = outcome {
                self?.missingPermission = permission
            } else {
                self?.missingPermission = nil
            }
        }
    }

    /// Opens the settings where that permission is kept, and stops saying anything about it.
    ///
    /// Cleared on the way out because the answer is no longer this app's to know: whatever the
    /// person does in that pane, the next click is what finds out.
    func openSettings(for permission: TerminalRaise.Permission) {
        missingPermission = nil
        TerminalRaiser.openSettings(for: permission)
    }

    /// Forgets the offer above. The panel closing is what calls this — a question left hanging
    /// expires with the panel, like the others.
    func forgetPermissionOffer() {
        missingPermission = nil
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
