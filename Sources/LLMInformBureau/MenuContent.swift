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
                if showsLimitsInFull {
                    limitsEntry(service)
                } else {
                    limitsSummary(service)
                }
            }
            limitsDisclosure

            Divider()
            caption("Active sessions — context")
            ForEach(model.sessions) { session in
                sessionEntry(session)
            }
            // A service that is merely idle is not listed: see `silentServices`.
            ForEach(silentServices, id: \.self) { service in
                silentEntry(service)
            }
            if model.sessions.isEmpty, silentServices.isEmpty {
                explanation("No active sessions.")
            }
            if let permission = model.missingPermission {
                permissionOffer(permission)
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
    /// The setting itself lives in the window behind the gear, where it was already being
    /// offered during setup — a panel of readings is not where a checkbox belongs, and one
    /// copy of a control cannot disagree with another. A gear rather than the question mark
    /// that was here before: the window it opens holds a setting and the list of what is
    /// connected, and a question mark promises reading rather than doing. Disconnecting is here for the same
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
            // Their own row within the row, tight: each icon carries its own plate under the
            // pointer, and the gap between two plates is what would otherwise read as a gap
            // between two groups.
            HStack(spacing: 0) {
                // Shown only while there is something to disconnect. An icon that is always
                // there and does nothing four times out of five is a control a person learns
                // to ignore.
                if model.slot.isOurs {
                    Button {
                        model.propose(.disconnect)
                    } label: {
                        Image(systemName: "bolt.slash").modifier(Hoverable())
                    }
                    .buttonStyle(.borderless)
                    .help(SlotPhrasing.disconnectHelp)
                }

                Button {
                    // The window is where a mark is moved, and the panel is what reads the
                    // marks — so it hands the window a way to ask for a pass when it closes.
                    // The checkup is read here rather than inside the window: the slot and
                    // the notification channel are the panel's own knowledge, and reading them
                    // twice is how two parts of one app come to disagree about the same fact.
                    Welcome.show(
                        checkup: CheckupReader.read(
                            slot: model.slot,
                            notifications: model.notificationChannel
                        ),
                        askForPass: { Task { await model.refresh() } }
                    )
                } label: {
                    Image(systemName: "gearshape").modifier(Hoverable())
                }
                .buttonStyle(.borderless)
                .help("Settings: where the numbers come from, what is connected, and whether to open at login")

                Button {
                    confirmingTerminate.toggle()
                } label: {
                    Image(systemName: "power").modifier(Hoverable())
                }
                .buttonStyle(.borderless)
                .help("Terminate the widget")
            }
            .padding(.trailing, -4)
        }
        // A question left hanging expires when the panel closes: reopening it should not find
        // a half-pressed decision from an hour ago. The same goes for a settings.json change
        // that was offered and neither taken nor refused.
        .onDisappear {
            confirmingTerminate = false
            model.cancelChange()
            model.forgetPermissionOffer()
        }
    }

    // MARK: The limits half, folded and opened out

    /// Whether the limits are shown in full.
    ///
    /// Folded by default, and the halves are not alike in this. A session's context moves
    /// several times a turn and is the reason the panel is opened at all; a limit window
    /// creeps, and the question it answers — "have I got room today" — is asked once in a
    /// while. In full it costs sixteen lines of a panel that has to hold every running
    /// session, and with ten of those open there is nothing left to hold them in.
    ///
    /// It opens itself for the one thing in that half that is not a reading: a change to
    /// `settings.json` waiting for an answer, or a complaint that one did not happen. Those
    /// have to be read, and a fold is no place to leave them.
    private var showsLimitsInFull: Bool {
        model.limitsExpanded || model.pendingChange != nil || model.slotProblem != nil
    }

    /// The one control that folds the limits away, at the foot of the half it folds.
    ///
    /// Under the readings rather than on the section's name, and saying what it gives rather
    /// than wearing a triangle and hoping. A caption in this panel is a label — every other one
    /// is — so a caption that was secretly a button was a control nobody would find. At the
    /// bottom, in the words of what it opens, it reads as the next line of the section and not
    /// as decoration.
    ///
    /// It goes away while a change to `settings.json` is waiting for an answer: that question
    /// is what the half is about at that moment, and folding it is not on offer.
    @ViewBuilder
    private var limitsDisclosure: some View {
        if model.pendingChange == nil {
            Button {
                model.limitsExpanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showsLimitsInFull ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                    Text(
                        showsLimitsInFull
                            ? "Show less"
                            : "Show both windows and when they reset"
                    )
                    .font(.caption)
                }
                .foregroundStyle(.secondary)
                .modifier(Hoverable())
            }
            .buttonStyle(.plain)
            .padding(.leading, -4)
        }
    }

    /// One service folded into a line: its light, its name, and the most spent of its windows.
    ///
    /// The worst window and not both, because that is the number the light is made of — the
    /// same one the menu bar shows — so the folded row and the dot beside it cannot say two
    /// different things. A service with nothing reported shows no number at all rather than a
    /// zero, the way everything else in this panel does — two words in its place instead, so
    /// that a row with nothing in it is never mistaken for a row that failed.
    @ViewBuilder
    private func limitsSummary(_ service: AgentService) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            StatusLight(light: model.lights(of: service).limits, diameter: 6)
                .alignmentGuide(.firstTextBaseline) { $0.height * 0.5 + 2.5 }
            Text(Wording.service(service))
                .font(.callout)
            Spacer()
            // The offer to connect keeps its place even folded away. It is the only thing in
            // this half that cannot wait to be opened out — until it is pressed there are no
            // limits to fold in the first place.
            if service == .claude, model.slot.isConnectable {
                Button(SlotPhrasing.connect) { model.propose(.connect) }
                    .controlSize(.small)
                    .help(SlotPhrasing.connectHelp)
            } else if let summary = summary(of: service) {
                // The window is named because two of them are being chosen between: a bare
                // percentage in a folded row is a number whose question is missing.
                Text(summary.window)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(summary.value)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if model.usage?.isInstalled(service) == true {
                // Installed, connected, and nothing reported yet. Two quiet words rather than
                // an empty half-row: right after the button is pressed this is the only place
                // a person is looking, and nothing there reads as nothing happening.
                Text(Wording.noReadingYet)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// What a folded service says on the right: which window, and how much of it is gone.
    /// Nothing at all when nobody has reported — never a zero.
    ///
    /// The five-hour window by default. It is the one that runs out during a working day, and
    /// it is the one a glance is asking about; the weekly one is a question people ask
    /// deliberately, which is what opening the section out is for.
    ///
    /// Two exceptions, and both are the same rule: the row must not disagree with the dot
    /// beside it. A window with nothing left is what the cross stands for, and a weekly window
    /// that has crossed a mark the five-hour one has not is the reason the dot is that
    /// colour — so each of those is the window shown.
    private func summary(of service: AgentService) -> (window: String, value: String)? {
        guard let assessment = model.limits[service] else { return nil }
        if let spent = assessment.spentWindow {
            return (Wording.limitWindowShort(spent.kind), Wording.spentLabel)
        }
        guard let snapshot = model.usage?.limits(of: service).value else { return nil }

        var kind = LimitWindow.Kind.short
        if case .limitUsage(let lit, _) = assessment.levelSource, lit == .weekly {
            kind = .weekly
        }
        guard let window = snapshot.window(kind) ?? snapshot.windows.first else { return nil }
        return (
            Wording.limitWindowShort(window.kind),
            "\(TokenDisplay.percent(window.usedPercent)) used"
        )
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
        case .oursElsewhere:
            // The one offer that stands under a working reading rather than in place of a
            // missing one: the numbers above it came through another copy of this app — the
            // old shell wrapper, or the same binary somewhere else — and this is the copy that
            // is running offering to carry them itself.
            Button(SlotPhrasing.takeOver) { model.propose(.connect) }
                .help(SlotPhrasing.takeOverHelp)
        case .unreadable(let path):
            explanation(SlotPhrasing.unreadable(path))
        case .ours:
            // Nothing reported yet. `ClaudeStatusStore` has the sentence for that, and it is
            // already above.
            EmptyView()
        }
        if model.slot.isOurs || model.slot.needsTakingOver,
           model.usage?.limits(of: .claude).value == nil {
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

    /// One running session's context budget — and, when there is a live process behind it, the
    /// way to the window it is running in.
    ///
    /// The plate under the pointer is the only thing that says a row is a control. It is the
    /// same plate every other control in this panel wears (`Hoverable`), and it appears only
    /// on rows that lead somewhere: a session with no process behind it is a reading like any
    /// other, and lighting it under the pointer would promise a window this app cannot find.
    @ViewBuilder
    private func sessionEntry(_ session: SessionView) -> some View {
        if session.snapshot.processID != nil {
            Button {
                model.raise(session.snapshot)
            } label: {
                sessionReadings(session).modifier(Hoverable())
            }
            .buttonStyle(.plain)
            .help(Wording.raiseSession)
            // The plate needs room around what it sits behind, and that room would move this
            // row's light out of line with the rows that have no plate. Taken back off the
            // outside, the column of lights stays a column — the same trick the disclosure
            // below the limits uses.
            .padding(.horizontal, -4)
            .padding(.vertical, -2)
        } else {
            sessionReadings(session)
        }
    }

    /// The readings themselves, laid out exactly like a limit window: what is being spent on
    /// the left, how much of it on the right, the detail underneath.
    private func sessionReadings(_ session: SessionView) -> some View {
        let snapshot = session.snapshot

        return entry(
            light: light(of: session),
            blinkedOut: blinkedOut(model.pulse(ofSession: snapshot.sessionID)),
            sign: model.sign(ofSession: snapshot.sessionID),
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
                sign: model.sign(ofSession: snapshot.sessionID)
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

    /// The services owed a line in the context half although they have no session to show —
    /// and only those with something to say.
    ///
    /// An idle service is left out. Its row said "No active sessions." under a heading that
    /// already says what the section is about, and it cost the panel a name, a dot and a line
    /// to repeat a fact the empty space was making anyway. Where a service stands in the
    /// widget does not depend on this: its limits keep their entry above, and its two dots
    /// keep their place in the bar.
    ///
    /// What does keep a row is a source that stopped making sense — an `.unavailable` reading
    /// from files that no longer parse. That is a reading, and one nobody would otherwise ever
    /// see: unlike an idle service, it does not explain itself by there being nothing there.
    /// A service that is not on the machine is left out too, and for the older reason — its own
    /// entry above has already said so, and saying it twice reads as two different problems.
    private var silentServices: [AgentService] {
        AgentService.allCases.filter { service in
            model.usage?.isInstalled(service) != false
                && !model.sessions.contains { $0.snapshot.service == service }
                && model.usage?.sessions(of: service).explanation != nil
        }
    }

    /// A service whose sessions could not be read: the same entry as a session, with the
    /// hollow dot that means "no reading" and the sentence for why. The light comes from the
    /// same rule the bar uses, so the panel cannot disagree with the bar about a service it
    /// knows nothing about.
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
        sign: LightSign? = nil,
        name: String,
        tag: String? = nil,
        badge: String?,
        help: String,
        @ViewBuilder rows: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StatusLight(light: light, sign: sign)
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

    /// What is left after a click that got the application and not the tab or window inside
    /// it: what happened, and the pane where that answer is kept.
    ///
    /// Shown only after a click, and gone when the panel closes. A permission nobody has
    /// wanted yet is not something to bring up — the whole point of asking at the moment of
    /// the click is that the dialog explains itself — and the app opens that pane itself
    /// rather than telling a person where to look, the way the limits button takes the status
    /// line slot itself.
    private func permissionOffer(_ permission: TerminalRaise.Permission) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            explanation(Wording.permissionOffer(permission, signedAdHoc: OwnSignature.isAdHoc))
            Button(Wording.permissionSettings(permission)) { model.openSettings(for: permission) }
                .controlSize(.small)
        }
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

/// A control that says it is one when the pointer is over it.
///
/// Everything else in this panel is a reading, and nothing here is styled to be clicked: a
/// caption looks like a caption and an icon like an icon. So the few things that do something
/// say so the only way a panel of text can — a plate behind them while the pointer is there,
/// and nothing at all the rest of the time, which is how the panel stays a page of numbers.
struct Hoverable: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.12 : 0))
            )
            // Animated, because the plate appearing instantly under a pointer that is only
            // passing through reads as the panel flickering rather than as an answer.
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
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

    /// The sign this light is drawn as instead of a dot, or `nil` for the dot itself. Shape
    /// carries the state and colour goes on carrying the budget — a session asked something
    /// with its window against the ceiling shows a red pause sign, which says both things at
    /// once and neither of them twice.
    var sign: LightSign?

    var body: some View {
        Group {
            if let sign {
                sign.path(in: CGRect(x: 0, y: 0, width: diameter, height: diameter))
                    .stroke(
                        colour(of: light),
                        style: StrokeStyle(
                            lineWidth: sign.lineWidth(forDiameter: diameter),
                            lineCap: .round
                        )
                    )
            } else {
                dot
            }
        }
        .frame(width: diameter, height: diameter)
    }

    /// The light as itself: a filled dot for a reading, an outline for none, a cross for a
    /// window with nothing left.
    @ViewBuilder
    private var dot: some View {
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
    }

    /// What colour a light of this kind is drawn in when it is drawn as a sign rather than as
    /// itself. An unreported reading keeps the grey its outline would have had: the sign says
    /// who is being waited on, and inventing a budget colour to go with it would say something
    /// nobody measured.
    private func colour(of light: Light) -> Color {
        switch light {
        case .unknown: .secondary
        case .level(let level): Palette.colour(of: level)
        case .spent: Palette.colour(of: .high)
        }
    }
}

/// A shape a light is drawn as instead of a dot, and the states that earn one.
///
/// Both of them answer the same question — who is being waited on — from opposite ends, which
/// is why they are one type and not two unrelated shapes: a light has at most one of them, and
/// the choice is made once, here.
///
/// Shape and colour say different things on purpose. The shape is the state; the colour goes on
/// being the budget, so a session asked something with its window against the ceiling wears a
/// red pause sign and says both at once. A third colour, or a fourth dot, would have said
/// neither clearly.
enum LightSign {
    /// A wait on the agent that has gone past the fuse: no answer for a long time. The figure
    /// eight.
    case stalled

    /// The agent has asked the person for something and stopped until they answer. The pause
    /// sign — two upright bars, the one shape everybody already reads as "stopped, and it is
    /// your move".
    case asking

    /// How thick the sign is stroked, given the diameter of the dot it replaces. Per sign
    /// rather than shared: the eight is one long stroke that closes on itself and reads at a
    /// hairline, while two short bars at that weight read as a gap between two flecks.
    func lineWidth(forDiameter diameter: Double) -> Double {
        switch self {
        case .stalled: max(diameter * 0.2, 1.1)
        case .asking: max(diameter * 0.26, 1.4)
        }
    }

    /// The sign as the panel draws it. The bar draws the same geometry through `NSBezierPath`,
    /// out of the same two enums below — one shape each, not two that merely resemble one
    /// another.
    func path(in box: CGRect) -> Path {
        switch self {
        case .stalled: WaitSign.path(in: box)
        case .asking: PauseSign.path(in: box)
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

/// The pause sign a light becomes while its agent is asking the person for something.
///
/// Two upright bars, drawn for the reason the eight and the cross are drawn: a glyph brings its
/// own line box and sits off-centre in a box six points wide, and a light's position is its
/// name. Strokes rather than filled rectangles, so the two signs are one drawing problem —
/// round caps, one line width, the same centre.
///
/// It overhangs the dot's slot upwards and downwards, where the eight overhangs it sideways:
/// each sign grows in the direction its own shape needs, and into padding that both the bar and
/// the panel have, so nothing beside a light moves when one appears. Half a diameter of bar
/// plus the round caps stands the sign about one and a sixth diameters tall against five
/// sixths wide — upright enough to read as a pause at six points, and the whole reason it is
/// legible there at all. The bars stand a quarter of a diameter apart: closer and they merge
/// into a stripe at that size, wider and the pair stops reading as one sign.
enum PauseSign {
    /// Half the length of a bar, and how far each stands from the centre — both as fractions
    /// of the light's diameter. The drawn height is larger than the first of them by the round
    /// caps, which add half a line width at each end.
    private static let halfHeight = 0.45
    private static let offset = 0.28

    /// Where the two bars run, top to bottom. Shared so that the bar's `NSBezierPath` and the
    /// panel's `Path` draw one shape and not two that merely resemble each other.
    static func bars(in box: CGRect) -> [(from: CGPoint, to: CGPoint)] {
        let reach = box.height * halfHeight
        let gap = box.width * offset
        return [-gap, gap].map { side in
            (
                from: CGPoint(x: box.midX + side, y: box.midY - reach),
                to: CGPoint(x: box.midX + side, y: box.midY + reach)
            )
        }
    }

    static func path(in box: CGRect) -> Path {
        Path { path in
            for bar in bars(in: box) {
                path.move(to: bar.from)
                path.addLine(to: bar.to)
            }
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
