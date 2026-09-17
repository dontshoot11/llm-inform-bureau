import AppKit
import SwiftUI
import AgentFiles
import Phrasing
import SessionHealthCore

/// The one window this app ever opens: the marks it watches, and everything it depends on.
///
/// Shown once, on the first launch, and then never again unless asked for from the panel. The
/// reason it exists at all is that two of the three sources connect themselves and one does
/// not — so a first run with no explanation is a menu bar item showing an em dash next to
/// "Claude" and no way to find out why. What has grown around that is the rest of the list:
/// every permission and every slot the app runs on fails the same quiet way, and none of it
/// looks like a missing answer from the outside.
///
/// AppKit rather than a SwiftUI `Window` scene: this app has `LSUIElement` set, so it is not
/// active when it launches, and a window has to be ordered in front and the app activated by
/// hand for anyone to see it.
@MainActor
enum Welcome {
    /// Held so the window is not deallocated the moment it is shown.
    private static var window: NSWindow?

    /// Held because a window's delegate is a weak reference and this one has no other owner.
    private static var closeWatcher: CloseWatcher?

    /// A pass of the panel, asked for by whoever opened this window — the panel is where the
    /// model lives, and this window is opened from it.
    private static var askForPass: (@MainActor () -> Void)?

    /// Whether a mark has been moved since the window was opened. A pass costs a read of
    /// everything that changed, and closing a window nobody touched is not a reason to spend
    /// one.
    private static var marksMoved = false

    /// Shows the explanation the first time the app runs, and records that it did.
    static func showIfDue(record: WelcomeRecord = WelcomeRecord()) {
        guard !record.hasBeenShown else { return }
        record.markShown()
        show()
    }

    /// A mark was moved in here. Said by the view, because closing the window is what acts on
    /// it and the window is what learns about the closing.
    static func marksChanged() {
        marksMoved = true
    }

    static func show(
        checkup: CheckupState = CheckupReader.read(),
        marks: ThresholdConfigLoad = ThresholdConfigLoader.load(),
        askForPass: (@MainActor () -> Void)? = nil
    ) {
        // Remembered whenever it is offered rather than only on the first showing: the first
        // run opens this window before there is a panel to ask, and the gear that opens it
        // afterwards is the one that knows how.
        if let askForPass { Self.askForPass = askForPass }

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = Briefing.windowTitle
        let content = NSHostingView(rootView: WelcomeView(checkup: checkup, marks: marks, close: close))
        window.contentView = content
        // Sized to what it actually holds — the marks come from the config and the list can
        // grow — but never taller than the screen it opens on.
        let wanted = content.fittingSize
        let room = (NSScreen.main?.visibleFrame.height ?? 800) - 80
        window.setContentSize(NSSize(width: wanted.width, height: min(wanted.height, room)))
        window.isReleasedWhenClosed = false
        window.center()
        let watcher = CloseWatcher { finishedWithTheWindow() }
        window.delegate = watcher
        Self.closeWatcher = watcher
        Self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Takes the focus ring off whatever holds it.
    ///
    /// A handle of the scale keeps the focus after it has been clicked, because that is what
    /// makes the arrow keys work on it — but nothing in this window took it back, so a mark
    /// touched once stayed ringed for the rest of the run. Clicking anywhere else is the
    /// gesture that means "done with that one", and the responder chain is where the ring
    /// actually lives.
    static func releaseFocus() {
        window?.makeFirstResponder(nil)
    }

    private static func close() {
        window?.close()
    }

    /// Closing the window is the moment a mark moved in it takes effect, whether it was closed
    /// with Done or with the red button.
    ///
    /// The marks are re-read on every pass anyway, so the change was never going to need a
    /// restart — but a pass is up to half a minute away, and half a minute of the old colour
    /// after pressing Done reads as the app having ignored you. So closing the window asks for
    /// one now.
    private static func finishedWithTheWindow() {
        guard marksMoved else { return }
        marksMoved = false
        askForPass?()
    }
}

/// Tells `Welcome` when its window closes. A window's delegate is a weak reference and an enum
/// cannot be one, so this exists to be held.
@MainActor
private final class CloseWatcher: NSObject, NSWindowDelegate {
    private let closed: () -> Void

    init(closed: @escaping () -> Void) {
        self.closed = closed
    }

    func windowWillClose(_ notification: Notification) {
        closed()
    }
}

/// The type scale of this window, in one place.
///
/// Four sizes and no more: a section's name, a line that names something, the explanation under
/// it and a number. They were picked one control at a time before this existed, and a window
/// where every block is set a little differently reads as several windows stacked up.
enum WindowType {
    /// The name of a section, folded or not.
    static let section = Font.callout.weight(.semibold)
    /// What a row is: a mark, a source, a piece of reading.
    static let item = Font.callout
    /// The line under a row, and every aside.
    static let detail = Font.caption
    /// A percentage, anywhere it is shown. Monospaced so a mark being dragged does not make
    /// the numbers beside it dance.
    static let number = Font.callout.monospacedDigit()
}

/// A section of this window that folds away.
///
/// The whole row opens and closes it and wears the same plate under the pointer as every other
/// control the app has (`Hoverable`): a chevron small enough to be decoration is not a target,
/// and a row that does something has to look like it does. Written rather than taken from
/// `DisclosureGroup`, which puts the click on the triangle alone and says nothing on hover.
private struct FoldingSection<Content: View>: View {
    let title: String
    @Binding var isOpen: Bool
    var spacing: Double = 8
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(WindowType.detail.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(WindowType.section)
                }
                .modifier(Hoverable())
            }
            .buttonStyle(.plain)
            .padding(.leading, -4)

            if isOpen {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The window, in the order it matters: the marks somebody came here to move, then the
/// background they rest on, then the checkup — everything the app runs on that this Mac had to
/// give it, folded away unless something in it is missing.
private struct WelcomeView: View {
    /// Everything this Mac has given the app, and what it has not.
    let checkup: CheckupState

    let config: ThresholdConfig

    /// The marks as the app itself would run on them. What "Reset to default" goes back to,
    /// and the reason it is kept beside the config rather than read out of it: the config in
    /// hand already has the person's choice in it.
    let shipped: ThresholdConfig

    let close: () -> Void

    /// Where the scales are right now, which is not always where the config says: the person
    /// may have moved them since this window was built, and it is built once per run.
    @State private var scales: [ThresholdMark: MarkScale]

    /// The same, for the marks that are one number.
    @State private var minutes: [ThresholdMark: Int]

    /// Whether the checkup is open. Closed when nothing in it is missing, because there is
    /// nothing to do about a thing that works; open while something is, because that is the one
    /// part of this window somebody has to act on.
    @State private var checkupOpen: Bool

    /// Whether the reading list is open. Closed to begin with: it is background, and a window
    /// that opens two screens tall makes the settings in it look like a footnote.
    @State private var readingOpen = false

    /// Which marks are theirs rather than the app's. Kept beside the values for the same
    /// reason: the config in hand was read before they touched anything, and the line under a
    /// mark must stop offering the shipped explanation the moment it stops describing it.
    @State private var chosen: Set<ThresholdMark>

    init(checkup: CheckupState, marks: ThresholdConfigLoad, close: @escaping () -> Void) {
        self.checkup = checkup
        self.config = marks.config
        self.shipped = marks.shipped
        self.close = close

        var scales: [ThresholdMark: MarkScale] = [:]
        var minutes: [ThresholdMark: Int] = [:]
        var chosen: Set<ThresholdMark> = []
        // Seeded off the list the window shows rather than off the config as a whole: a mark
        // this window has no row for is a mark nobody can move in it.
        for note in Briefing.marks(of: marks.config) {
            if let scale = marks.config.scaleMarks(of: note.mark) {
                scales[note.mark] = MarkScale(of: scale)
            }
            if let duration = marks.config.duration(of: note.mark) {
                minutes[note.mark] = duration.minutes
            }
            if note.isChosen { chosen.insert(note.mark) }
        }
        _scales = State(initialValue: scales)
        _minutes = State(initialValue: minutes)
        _chosen = State(initialValue: chosen)
        _checkupOpen = State(initialValue: checkup.hasSomethingMissing)
    }

    var body: some View {
        ScrollView {
            content
        }
        .frame(width: 460)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            // The marks come first: they are the part of this window somebody came here to
            // work, and everything under them is an explanation they can open when they want
            // one.
            // Read out of the config, so this list cannot claim a number the app does not use.
            Text(Briefing.marksTitle)
                .font(WindowType.section)
            // What the colours are like to be in, above the marks that say where each of them
            // begins. The marks are numbers on a scale; this is the scale's other half, and
            // the half a person cannot work out from a dot.
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Briefing.levelKey, id: \.level) { meaning in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        StatusLight(light: .level(meaning.level), diameter: 7)
                            .alignmentGuide(.firstTextBaseline) { $0.height * 0.5 + 2.5 }
                        Text(meaning.meaning)
                            .font(WindowType.detail)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.bottom, 2)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Briefing.marks(of: config), id: \.mark) { mark in
                    markRow(mark)
                }
            }

            Divider()

            // Folded away, and opened by whoever wants it. It is the longest thing in this
            // window and the only part nobody has to read to use the app: it is here so the
            // premise behind the marks can be checked, which is a thing somebody does once.
            FoldingSection(title: Briefing.furtherReadingTitle, isOpen: $readingOpen) {
                Text(Briefing.furtherReadingNote)
                    .font(WindowType.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Briefing.furtherReading, id: \.title) { reading in
                    readingRow(reading)
                }
            }

            Divider()

            // Everything the app depends on and did not bring with it. Folded away once
            // nothing in it is missing — there is nothing to do about what works — and open by
            // itself while something is, which is the whole reason the list exists: every one
            // of these fails quietly, and a widget that has not been allowed to do its job
            // looks exactly like a broken one.
            FoldingSection(title: CheckupPhrasing.title, isOpen: $checkupOpen, spacing: 12) {
                Text(CheckupPhrasing.intro)
                    .font(WindowType.item)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(CheckupPhrasing.rows(for: checkup), id: \.point) { row in
                    checkupRow(row)
                }
                Text(CheckupPhrasing.closing)
                    .font(WindowType.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(alignment: .firstTextBaseline) {
                Spacer()
                Button("Done", action: close)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, alignment: .leading)
        // A click on the window that is not a click on a control ends whatever was being
        // adjusted. Buttons, links and the handles themselves take their own clicks first.
        .contentShape(Rectangle())
        .onTapGesture { Welcome.releaseFocus() }
    }

    /// One mark, as this window hands it over: what it is, the control that sets it, and the
    /// line saying who put it where it is.
    ///
    /// One row for both kinds of mark. A scale gets the bar — a picture of the marks that is
    /// also the way to move them — and a mark that is one number gets a field beside its title;
    /// everything else about the row is the same, because to the reader they are the same kind
    /// of thing.
    private func markRow(_ mark: MarkNote) -> some View {
        let scale = config.scaleMarks(of: mark.mark)
        let isChosen = chosen.contains(mark.mark)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(mark.title)
                    .font(WindowType.item)
                    // Onto a second line rather than into an ellipsis: a row that reads
                    // "Announce a request for…" beside a field of minutes says nothing.
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let duration = config.duration(of: mark.mark) {
                    MinuteMarkField(
                        title: mark.title,
                        minutes: minutes(of: mark.mark, orShipped: duration.minutes),
                        settled: { choose(mark.mark, minutes: $0) }
                    )
                }
                // Only on a mark that was actually moved: a button with nothing to undo is one
                // more control to read past, and this window is already a list of them.
                if isChosen {
                    Button(Briefing.resetMark) { reset(mark.mark) }
                        .buttonStyle(.link)
                        .font(WindowType.detail)
                }
            }
            if let scale {
                MarkScaleBar(
                    title: mark.title,
                    scale: self.scale(of: mark.mark, orShipped: scale),
                    settled: { choose(mark.mark, $0) }
                )
                // The title is the label of the bar, not a line of the bar: without the gap
                // the two read as one crowded block.
                .padding(.top, 4)
            }
            // Nothing under a mark that was moved: what stood here explained a number that is
            // no longer there, and the Reset button beside the title is what says the mark is
            // the reader's own.
            if !isChosen {
                HStack(spacing: 6) {
                    Text(mark.note)
                        .font(WindowType.detail)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let source = mark.source {
                        Link("source", destination: source)
                            .font(WindowType.detail)
                    }
                }
            }
            // Under the bar alone: dragging is discoverable and the arrow keys are not, while
            // a field with a stepper beside it says how it is worked by being one.
            if scale != nil {
                Text(Briefing.markEditHint)
                    .font(WindowType.detail)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Where a scale is right now, falling back to what the app ships when this window has
    /// somehow not seeded it — a mark with no state is a row that cannot be drawn, and the
    /// shipped numbers are the right thing to draw instead of nothing.
    private func scale(of mark: ThresholdMark, orShipped marks: PercentMarks) -> Binding<MarkScale> {
        Binding(
            get: { scales[mark] ?? MarkScale(of: marks) },
            set: { scales[mark] = $0 }
        )
    }

    private func minutes(of mark: ThresholdMark, orShipped value: Int) -> Binding<Int> {
        Binding(
            get: { minutes[mark] ?? value },
            set: { minutes[mark] = $0 }
        )
    }

    /// Writes down a scale that has just been moved, keeping every other choice on disk: this
    /// window is not the only thing that will ever write to that file, and a choice is a choice
    /// about one mark rather than a snapshot of all of them.
    ///
    /// The panel is not redrawn here. It re-reads the marks on every pass of its own, and a
    /// menu bar that redrew itself on every step of a drag would be a second path to the same
    /// reading; what closing the window does instead is ask for one pass, once
    /// (`Welcome.marksChanged`).
    private func choose(_ mark: ThresholdMark, _ scale: MarkScale) {
        chosen.insert(mark)
        Welcome.marksChanged()
        write { $0.choosing(mark, scale) }
    }

    private func choose(_ mark: ThresholdMark, minutes value: Int) {
        chosen.insert(mark)
        Welcome.marksChanged()
        write { $0.choosing(mark, minutes: value) }
    }

    /// Puts a mark back where the app had it, and takes the choice off the disk rather than
    /// writing the shipped numbers down as a choice of their own — the mark goes back to
    /// following the app, including through the releases that move it.
    private func reset(_ mark: ThresholdMark) {
        if let marks = shipped.scaleMarks(of: mark) { scales[mark] = MarkScale(of: marks) }
        if let duration = shipped.duration(of: mark) { minutes[mark] = duration.minutes }
        chosen.remove(mark)
        Welcome.marksChanged()
        write { $0.forgetting(mark) }
    }

    /// One change to what is on disk, made against whatever is there rather than against what
    /// this window was built with.
    private func write(_ change: (ThresholdChoices) -> ThresholdChoices) {
        let url = ThresholdChoicesStore.url()
        ThresholdChoicesStore.write(change(ThresholdChoicesStore.read(at: url)), to: url)
    }

    /// One piece of background: its title as a link, the year, and what it shows in a line.
    private func readingRow(_ reading: Reading) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let source = reading.source {
                    Link(reading.title, destination: source)
                        .font(WindowType.item)
                } else {
                    Text(reading.title)
                        .font(WindowType.item)
                }
                Text(reading.year)
                    .font(WindowType.detail)
                    .foregroundStyle(.secondary)
            }
            Text(reading.note)
                .font(WindowType.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One line of the checkup: what the machine says, what it is, what it costs while the
    /// answer is no, and the pane where that answer is kept.
    ///
    /// One row for a source, a permission and a fact about this copy alike. To the reader they
    /// are the same kind of thing — something the app runs on that it did not bring with it —
    /// and a list that changed shape halfway down would read as two lists.
    private func checkupRow(_ row: CheckupRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            standingMark(row.standing)
            VStack(alignment: .leading, spacing: 2) {
                // The one line here that is a control rather than a reading: the checkbox is
                // both what the row says and the way to change it, so it stands where the
                // title would.
                if row.point == .openAtLogin {
                    LoginItemToggle(loginItem: .shared)
                } else {
                    Text(row.title)
                        .font(WindowType.item)
                }
                Text(row.detail)
                    .font(WindowType.item)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    // The path of the running copy is in here, and the thing anybody does with
                    // a path is copy it somewhere else.
                    .textSelection(.enabled)
                if let pane = row.settings {
                    Button(Wording.openSettings(pane)) { SystemSettings.open(pane) }
                        .buttonStyle(.link)
                        .font(WindowType.detail)
                }
            }
        }
    }

    /// What the machine said, as one mark before the line.
    ///
    /// Four and not two: a question mark for what macOS will not answer until the app tries,
    /// and a plain note for a line that states a fact rather than reporting a permission. A
    /// tick invented for either would be the app's guess wearing the system's authority.
    @ViewBuilder
    private func standingMark(_ standing: CheckupState.Standing) -> some View {
        switch standing {
        case .given:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
        case .missing:
            Image(systemName: "circle.dashed").foregroundStyle(Color.secondary)
        case .settledOnUse:
            Image(systemName: "questionmark.circle").foregroundStyle(Color.secondary)
        case .stated:
            Image(systemName: "info.circle").foregroundStyle(.tertiary)
        }
    }
}
