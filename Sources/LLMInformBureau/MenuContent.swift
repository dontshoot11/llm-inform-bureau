import AppKit
import SwiftUI
import AgentFiles
import Phrasing
import SessionHealthCore

/// The panel behind the menu bar title.
///
/// Two halves: what the subscription has cost so far, and what the sessions running right now
/// hold. Every place a number could be missing says a sentence instead — the one thing this
/// panel must never do is show a confident 0% for something it does not know.
struct MenuContent: View {
    @ObservedObject var model: UsageModel

    /// Whether the power icon has been pressed once. Quitting is two taps rather than one
    /// because the panel is opened to read something, and the icon sits where a thumb lands.
    @State private var confirmingTerminate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The panel's two halves are named, because the bar's two dots are exactly these
            // two subjects and nothing else says which is which. They are also built by the
            // same two helpers below, so neither half can drift into looking more important
            // than the other.
            caption("Subscription limits")
            ForEach(AgentService.allCases, id: \.self) { service in
                limitsEntry(service)
            }

            Divider()
            caption("Active sessions — context")
            ForEach(model.sessions) { session in
                sessionEntry(session)
            }
            // A service with nothing to show keeps its place here, hollow dot and all: silence
            // about a source is a reading of its own, and an empty space beside the other
            // service's sessions reads as a service that is fine. An agent that is not on the
            // machine is skipped: its own entry above has already said so, and saying it twice
            // reads as two different problems.
            ForEach(silentServices, id: \.self) { service in
                silentEntry(service)
            }
            if model.sessions.isEmpty, silentServices.isEmpty {
                explanation("No active sessions.")
            }

            if let reason = model.levelReason {
                Divider()
                // The same light the bar is showing, so the line that explains a cross is
                // marked with one.
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    StatusLight(light: model.levelLight, diameter: 6)
                        // A shape has no baseline of its own, so it would sit on the line
                        // instead of in it. This puts its middle where the lower-case letters
                        // are, which is where a reader expects a bullet.
                        .alignmentGuide(.firstTextBaseline) { $0.height * 0.5 + 2.5 }
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !model.configProblems.isEmpty {
                Divider()
                configProblems
            }

            Divider()
            settings
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
    }

    // MARK: Settings

    /// One quiet row of icons: the way out of the status line slot, the way back to the
    /// explanation, and the way out of the app.
    ///
    /// The setting itself lives in the window behind the question mark, where it was already
    /// being offered during setup — a panel of readings is not where a checkbox belongs, and
    /// one copy of a control cannot disagree with another. Disconnecting is here for the same
    /// reason: it acts on the app rather than on a reading, and putting it under the limits
    /// would leave the place a person reads a number carrying a way to take that number away.
    private var settings: some View {
        HStack(spacing: 8) {
            if confirmingTerminate {
                Text("Terminate?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Yes") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.defaultAction)
                // Both answers are on screen: a question with one button offers no way to say
                // no except to guess that clicking elsewhere means no.
                Button("No") { confirmingTerminate = false }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            // Shown only while there is something to disconnect. An icon that is always there
            // and does nothing four times out of five is a control a person learns to ignore.
            if model.slot.isOurs {
                Button {
                    model.propose(.disconnect)
                } label: {
                    Image(systemName: "bolt.slash")
                }
                .buttonStyle(.borderless)
                .help(SlotPhrasing.disconnectHelp)
            }

            Button {
                Welcome.show()
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Where the numbers come from, and whether to open at login")

            Button {
                confirmingTerminate.toggle()
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Terminate the widget")
        }
        // A question left hanging expires when the panel closes: reopening it should not find
        // a half-pressed decision from an hour ago. The same goes for a settings.json change
        // that was offered and neither taken nor refused.
        .onDisappear {
            confirmingTerminate = false
            model.cancelChange()
        }
    }

    // MARK: The two halves

    /// One service's limit windows — or, for an agent that is not on this machine, the one line
    /// that says so. It keeps its place in the panel and its lights in the bar: a service that
    /// vanished would leave no way to learn the widget covers it.
    @ViewBuilder
    private func limitsEntry(_ service: AgentService) -> some View {
        let reading = model.usage?.limits(of: service) ?? .noData("Reading…")

        entry(
            light: model.lights(of: service).limits,
            name: Wording.service(service),
            badge: reading.value?.planType,
            help: "This service's subscription limits — the first of its two dots in the menu bar. "
                + Briefing.scaleHelp(model.thresholds)
        ) {
            if model.usage?.isInstalled(service) == false {
                explanation(Wording.notInstalled)
            } else if service == .claude, let change = model.pendingChange {
                // Everything else about this reading steps aside while a change to somebody's
                // settings.json is on the table: it is the one thing in this panel that does
                // something rather than reports something, and it is read before it is agreed
                // to or not at all.
                changePreview(change)
            } else if let snapshot = reading.value {
                ForEach(snapshot.windows, id: \.kind) { window in
                    row(
                        Wording.limitWindow(window.kind, minutes: window.windowMinutes),
                        value: "\(TokenDisplay.percent(window.usedPercent)) used",
                        note: window.resetsAt.map { "resets \(TimeDisplay.until($0))" } ?? "reset time not reported"
                    )
                }
                explanation("Reported \(TimeDisplay.age(of: snapshot.observedAt))")
                hint(Wording.limitsCommand(service))
                if service == .claude { slotOffer }
            } else if service == .claude, model.usage != nil {
                // No numbers and none coming: the button is the whole of what this place says.
                // A sentence explaining the absence would be the third thing in a row that
                // says "nothing here" and the only one of them that cannot be acted on.
                //
                // Not before the first reading has landed, though: at that point nothing has
                // looked at the slot yet, and a button offering to connect something that is
                // already connected would flash up on every launch.
                slotOffer
            } else {
                explanation(reading.explanation ?? "")
            }
        }
    }

    /// What the Claude limits entry offers about the one thing on this Mac that has to be
    /// connected by hand.
    ///
    /// It stands where the numbers would be, and that is the point: the place a person looks
    /// for a figure is the place that should tell them how to get one. While the slot is the
    /// app's there is nothing to offer here — the way back out is a control among the panel's
    /// other controls, not an action sitting under a reading.
    @ViewBuilder
    private var slotOffer: some View {
        switch model.slot {
        case .free, .somebodyElse:
            Button(SlotPhrasing.connect) { model.propose(.connect) }
                .help(SlotPhrasing.connectHelp)
        case .unreadable(let path):
            explanation(SlotPhrasing.unreadable(path))
        case .ours:
            // Nothing reported yet. `ClaudeStatusStore` has the sentence for that, and it is
            // already above.
            EmptyView()
        }
        if model.slot.isOurs, model.usage?.limits(of: .claude).value == nil {
            explanation(model.usage?.limits(of: .claude).explanation ?? "")
        }
        if let problem = model.slotProblem {
            explanation(problem)
        }
    }

    /// The edit to `settings.json`, before it is made: the file, the line going into it, and
    /// what happens to what is already there. Then the two answers.
    ///
    /// Both buttons are on screen for the same reason the quit confirmation has two: a
    /// question with one button leaves saying no to guesswork about where to click.
    private func changePreview(_ change: StatusLineChange) -> some View {
        let preview = SlotPhrasing.preview(change)

        return VStack(alignment: .leading, spacing: 6) {
            explanation(preview.title)
            Text(preview.path)
                .font(.caption.monospaced())
                .fixedSize(horizontal: false, vertical: true)
            if let command = preview.command {
                Text(command)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(preview.notes, id: \.self) { note in
                explanation(note)
            }
            HStack {
                Button(SlotPhrasing.apply) { model.applyChange() }
                    .keyboardShortcut(.defaultAction)
                Button(SlotPhrasing.cancel) { model.cancelChange() }
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    /// One running session's context budget, laid out exactly like a limit window: what is
    /// being spent on the left, how much of it on the right, the detail underneath.
    private func sessionEntry(_ session: SessionView) -> some View {
        let snapshot = session.snapshot

        return entry(
            light: light(of: session),
            blinkedOut: blinkedOut(model.pulse(ofSession: snapshot.sessionID)),
            stalled: model.isStalled(session: snapshot.sessionID),
            name: Wording.service(snapshot.service),
            tag: snapshot.model,
            badge: snapshot.project,
            help: "The context this session holds — the second of its service's two dots in the menu bar. "
                + Briefing.scaleHelp(model.thresholds)
        ) {
            row("Context window", value: fill(of: snapshot), note: detail(of: snapshot))
            ForEach(session.subagents) { subagent in
                subagentRow(subagent)
            }
            hint(Wording.contextCommand(snapshot.service))
        }
    }

    /// A subagent of the session above it: indented, lit by its own mark, and quieter than the
    /// session's own row.
    ///
    /// The indent and the smaller light are the whole of what says "this is not a session" —
    /// an agent holds a context of its own and is measured on the same scale, so anything more
    /// emphatic would suggest a difference in the reading rather than in whose reading it is.
    private func subagentRow(_ subagent: SessionView) -> some View {
        let snapshot = subagent.snapshot

        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            StatusLight(
                light: light(of: subagent),
                diameter: 6,
                stalled: model.isStalled(session: snapshot.sessionID)
            )
                .opacity(blinkedOut(model.pulse(ofSession: snapshot.sessionID)) ? 0 : 1)
                .alignmentGuide(.firstTextBaseline) { $0.height * 0.5 + 2.5 }
                .help(
                    "A subagent started by this session. It runs on the session's context window "
                        + "unless it was given a model of its own, and its mark never notifies: it "
                        + "ends by itself, usually within minutes."
                )
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Wording.subagentName(snapshot.subagent?.type))
                        .font(.caption)
                    Spacer()
                    Text(fill(of: snapshot))
                        .font(.caption.monospacedDigit())
                }
                explanation(subagentDetail(of: snapshot))
            }
        }
        .padding(.leading, 12)
    }

    /// What the agent was asked to do, and what it holds. The task first: it is what tells two
    /// agents of the same kind apart.
    private func subagentDetail(of snapshot: SessionSnapshot) -> String {
        var parts: [String] = []
        if let task = Wording.subagentTask(snapshot.subagent?.task) { parts.append(task) }
        parts.append("\(TokenDisplay.short(snapshot.contextTokens)) tokens held")
        return parts.joined(separator: " · ")
    }

    /// The services owed a line in the context half although they have no session to show:
    /// installed, and silent. One that is not on the machine is left out on purpose — see the
    /// panel above.
    private var silentServices: [AgentService] {
        AgentService.allCases.filter { service in
            model.usage?.isInstalled(service) != false
                && !model.sessions.contains { $0.snapshot.service == service }
        }
    }

    /// A service with nothing running: the same entry as a session, with the hollow dot that
    /// means "no reading" and the sentence for why. The light comes from the same rule the bar
    /// uses, so the panel cannot disagree with the bar about a service it knows nothing about.
    private func silentEntry(_ service: AgentService) -> some View {
        entry(
            light: model.lights(of: service).context,
            name: Wording.service(service),
            badge: nil,
            help: "The context this service's sessions hold — the second of its two dots in the "
                + "menu bar. " + Briefing.scaleHelp(model.thresholds)
        ) {
            explanation(model.usage?.sessions(of: service).explanation ?? "No active sessions.")
        }
    }

    /// The light one row shows — a session's or a subagent's, the rule is the same.
    ///
    /// A reading whose window size nobody reported has no share to place on the scale, so its
    /// light says "no reading" rather than the green that every other unplaceable number in
    /// this app is careful not to show.
    /// Whether a light is dark for this frame of its pulse — the same blink the menu bar does,
    /// on the same phase, so the bar and the panel go out together rather than each on its own
    /// beat. The rule itself lives with the drawing in `BarLights`; this is its one-line twin
    /// for views, which cannot call into that drawing code.
    private func blinkedOut(_ phase: Double?) -> Bool {
        guard let phase else { return false }
        return Int(phase * BarLights.blinkFrames) % 2 == 0
    }

    private func light(of view: SessionView) -> Light {
        view.assessment.windowFillPercent == nil ? .unknown : .level(view.assessment.level)
    }

    /// How much of the window is gone, or a sentence when nothing knows the window. Never a
    /// percentage of something unknown.
    private func fill(of snapshot: SessionSnapshot) -> String {
        guard let fill = snapshot.windowFillPercent, let window = snapshot.contextWindowTokens else {
            return "size unknown"
        }
        return "\(TokenDisplay.percent(fill)) of \(TokenDisplay.short(window))"
    }

    /// What is held, and what the last request added to it.
    ///
    /// "Request" rather than the domain's own word: a turn is what the rules measure between
    /// two user prompts, and a person reading the panel calls that the last thing they asked
    /// for.
    private func detail(of snapshot: SessionSnapshot) -> String {
        var parts = ["\(TokenDisplay.short(snapshot.contextTokens)) tokens held"]
        if let growth = snapshot.turnGrowthTokens {
            parts.append("\(TokenDisplay.growth(growth)) last request")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: The shape both halves share

    /// One entry of either half: a lit name, something secondary on the right, rows beneath.
    private func entry(
        light: Light,
        blinkedOut: Bool = false,
        stalled: Bool = false,
        name: String,
        tag: String? = nil,
        badge: String?,
        help: String,
        @ViewBuilder rows: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StatusLight(light: light, stalled: stalled)
                    // Hidden rather than removed: the row must not shift sideways while it
                    // blinks, or the blink reads as the layout moving instead of the light.
                    .opacity(blinkedOut ? 0 : 1)
                    .help(help)
                Text(name)
                    .font(.headline)
                if let tag {
                    // In the font the command hints are set in, and for the same reason: it is
                    // the identifier the CLI itself uses, not prose about the session. Set
                    // against the name rather than off to the right, because it says what this
                    // "Claude" currently is — the right edge belongs to the project, and is the
                    // first thing to be truncated on a narrow panel.
                    Text(tag)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            rows()
        }
    }

    /// One row of either half: what is being spent, how much of it, and the detail beneath.
    private func row(_ title: String, value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(title)
                    .font(.callout)
                Spacer()
                Text(value)
                    .font(.callout.monospacedDigit())
            }
            explanation(note)
        }
    }

    // MARK: Odds and ends

    private var configProblems: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Default thresholds applied")
                .font(.caption.weight(.medium))
            ForEach(model.configProblems, id: \.self) { problem in
                explanation(problem)
            }
        }
    }

    /// The command that shows the rest of a reading in the CLI.
    ///
    /// The panel answers "how much", and the next question is always "and how do I see the
    /// rest" — the same reason a notification ends with it. Monospaced, because it is something
    /// to type rather than something to read.
    private func hint(_ command: String) -> some View {
        Text(Wording.moreDetails(command))
            .font(.caption.monospaced())
            .foregroundStyle(.tertiary)
    }

    /// A section's name: quiet, above the section, in the words the bar's dots go by.
    private func caption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }

    private func explanation(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One light, as the panel draws it: a dot for a reading, an outline for none, a cross for a
/// window with nothing left.
///
/// The outline is the point of the middle case. A single dot used to fall back to green for an
/// unreported reading, which said "all good" about something nobody had measured — the one
/// thing the panel forbids everywhere else. The panel can afford an outline where the bar
/// cannot, because here a sentence explaining the absence stands next to it.
struct StatusLight: View {
    let light: Light
    var diameter: Double = 8

    /// Whether this light stands for a wait that has gone past the fuse: the same light in the
    /// same colour, drawn as a figure eight instead of a dot. Shape carries the state and
    /// colour goes on carrying the budget — a context against the ceiling shows a red sign,
    /// which says both things at once and neither of them twice.
    var stalled: Bool = false

    var body: some View {
        Group {
            switch light {
            case _ where stalled:
                WaitSign.path(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
                    .stroke(
                        colour(of: light),
                        style: StrokeStyle(
                            lineWidth: WaitSign.lineWidth(forDiameter: diameter),
                            lineCap: .round
                        )
                    )
            case .unknown:
                Circle().strokeBorder(Color.secondary, lineWidth: 1.5)
            case .level(let level):
                Circle().fill(Palette.colour(of: level))
            case .spent:
                // Drawn rather than an SF Symbol: a glyph carries its own line height and sits
                // off-centre in a box this small, and this cross has to line up with the dots
                // it stands in for.
                Path { path in
                    let inset = diameter * 0.14
                    path.move(to: CGPoint(x: inset, y: inset))
                    path.addLine(to: CGPoint(x: diameter - inset, y: diameter - inset))
                    path.move(to: CGPoint(x: inset, y: diameter - inset))
                    path.addLine(to: CGPoint(x: diameter - inset, y: inset))
                }
                .stroke(
                    Palette.colour(of: .high),
                    style: StrokeStyle(lineWidth: max(diameter * 0.22, 1.2), lineCap: .round)
                )
            }
        }
        .frame(width: diameter, height: diameter)
    }

    /// What colour a light of this kind is drawn in when it is drawn as a sign rather than as
    /// itself. An unreported reading keeps the grey its outline would have had: the sign says
    /// the wait is long, and inventing a budget colour to go with it would say something nobody
    /// measured.
    private func colour(of light: Light) -> Color {
        switch light {
        case .unknown: .secondary
        case .level(let level): Palette.colour(of: level)
        case .spent: Palette.colour(of: .high)
        }
    }
}

/// The figure eight a light becomes when the wait behind it has gone past the fuse.
///
/// Drawn rather than taken from SF Symbols, for the reason the cross above is: a glyph brings
/// its own line box and sits off-centre in a box six points wide, and this sign has to line up
/// with the dots it stands among. Two cubics, each leaving the centre and coming back to it,
/// which is the shortest description of a lemniscate that a bezier path can hold.
///
/// It keeps the dot's slot and its centre, and overhangs it by about an eighth of a diameter on
/// each side — into padding both in the bar and in the panel, so nothing next to it moves. That
/// overhang is the whole reason the sign reads at menu bar size at all: a figure eight squeezed
/// into the width of a six-point dot is a smudge, and the position of a light is its name.
enum WaitSign {
    /// Half the sign's width and height, as fractions of the light's diameter.
    private static let halfWidth = 0.62
    private static let halfHeight = 0.33

    /// What a cubic that starts and ends at one point reaches, as a fraction of its control
    /// offset: three quarters of it sideways, and 0.2887 of it at the widest point of the lobe.
    /// Dividing by them is what makes the sign come out the size it was asked for rather than
    /// roughly that.
    private static let sidewaysReach = 0.75
    private static let verticalReach = 0.2887

    static func lineWidth(forDiameter diameter: Double) -> Double { max(diameter * 0.2, 1.1) }

    /// The centre, and the two control offsets that put each lobe where it belongs. Shared so
    /// that the bar's `NSBezierPath` and the panel's `Path` draw one shape and not two that
    /// merely resemble each other.
    static func lobes(in box: CGRect) -> (centre: CGPoint, reach: Double, lift: Double) {
        (
            CGPoint(x: box.midX, y: box.midY),
            box.width * halfWidth / sidewaysReach,
            box.height * halfHeight / verticalReach
        )
    }

    static func path(in box: CGRect) -> Path {
        let (centre, reach, lift) = lobes(in: box)
        return Path { path in
            path.move(to: centre)
            path.addCurve(
                to: centre,
                control1: CGPoint(x: centre.x - reach, y: centre.y + lift),
                control2: CGPoint(x: centre.x - reach, y: centre.y - lift)
            )
            path.addCurve(
                to: centre,
                control1: CGPoint(x: centre.x + reach, y: centre.y - lift),
                control2: CGPoint(x: centre.x + reach, y: centre.y + lift)
            )
        }
    }
}

/// The four levels, as the panel colours them.
///
/// Orange rather than a second yellow: the menu bar is read at a glance and out of the corner
/// of an eye, and two shades of the same hue are one colour at that size. The step from yellow
/// to orange is the step from "worth knowing" to "worth saying", and it has to survive being
/// four points wide on a dark strip.
enum Palette {
    static func colour(of level: BudgetLevel) -> Color {
        switch level {
        case .normal: .green
        case .notice: .yellow
        case .elevated: .orange
        case .high: .red
        }
    }
}
