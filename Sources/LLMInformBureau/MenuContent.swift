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

    /// One quiet row of two icons: the way back to the explanation, and the way out.
    ///
    /// The setting itself lives in the window behind the first icon, where it was already
    /// being offered during setup — a panel of readings is not where a checkbox belongs, and
    /// one copy of a control cannot disagree with another.
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
        // a half-pressed decision from an hour ago.
        .onDisappear { confirmingTerminate = false }
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
            } else {
                explanation(reading.explanation ?? "")
            }
        }
    }

    /// One running session's context budget, laid out exactly like a limit window: what is
    /// being spent on the left, how much of it on the right, the detail underneath.
    private func sessionEntry(_ session: SessionView) -> some View {
        let snapshot = session.snapshot

        return entry(
            light: light(of: session),
            name: Wording.service(snapshot.service),
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
            StatusLight(light: light(of: subagent), diameter: 6)
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
        name: String,
        badge: String?,
        help: String,
        @ViewBuilder rows: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StatusLight(light: light)
                    .help(help)
                Text(name)
                    .font(.headline)
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

    var body: some View {
        Group {
            switch light {
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
