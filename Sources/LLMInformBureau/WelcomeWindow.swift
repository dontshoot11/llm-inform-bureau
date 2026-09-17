import AppKit
import SwiftUI
import AgentFiles
import Phrasing
import SessionHealthCore

/// The one window this app ever opens: what it reads, and what is not connected yet.
///
/// Shown once, on the first launch, and then never again unless asked for from the panel. The
/// reason it exists at all is that two of the three sources connect themselves and one does
/// not — so a first run with no explanation is a menu bar item showing an em dash next to
/// "Claude" and no way to find out why.
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
        state: SetupState = SetupInspector.inspect(),
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
        let content = NSHostingView(rootView: WelcomeView(state: state, marks: marks, close: close))
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

/// What the first run says, in the order it matters: how the app gets its numbers, then each
/// source with whether it is connected, then what an unconnected source looks like in the
/// panel.
private struct WelcomeView: View {
    let state: SetupState
    let config: ThresholdConfig

    /// The marks as the app itself would run on them. What "Reset to default" goes back to,
    /// and the reason it is kept beside the config rather than read out of it: the config in
    /// hand already has the person's choice in it.
    let shipped: ThresholdConfig

    let close: () -> Void

    /// Where the limit marks are right now, which is not always where the config says: the
    /// person may have moved them since this window was built, and it is built once per run.
    @State private var limitScale: MarkScale

    /// Whether the list of sources is open. Closed when every source has reported, because
    /// there is nothing to do about one that works; open while something is missing, because
    /// that is the one thing in this window somebody has to act on.
    @State private var sourcesOpen: Bool

    /// Whether the reading list is open. Closed to begin with: it is background, and a window
    /// that opens two screens tall makes the settings in it look like a footnote.
    @State private var readingOpen = false

    /// Whether the limit marks are theirs rather than the app's. Kept beside the scale for the
    /// same reason: the config in hand was read before they touched it, and the line under the
    /// bar must stop offering the shipped explanation the moment it stops describing the mark.
    @State private var limitChosen: Bool

    init(state: SetupState, marks: ThresholdConfigLoad, close: @escaping () -> Void) {
        self.state = state
        self.config = marks.config
        self.shipped = marks.shipped
        self.close = close
        _limitScale = State(initialValue: MarkScale(of: marks.config.limitUsage))
        _limitChosen = State(initialValue: marks.config.limitUsage.isChosen)
        _sourcesOpen = State(initialValue: !state.isComplete)
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
                    // The limit scale is the one a person can move here. The rest are shown as
                    // they are set, and are not read-only on principle — they are the marks
                    // this window has not grown a control for yet.
                    if mark.mark == .limitUsage {
                        editableMarkRow(mark)
                    } else {
                        markRow(mark)
                    }
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

            // Where the readings come from. Folded away once every source has reported —
            // there is nothing to do about a source that is working — and open by itself
            // while one of them is missing, which is the whole reason this window exists:
            // two of the three connect themselves and one does not.
            FoldingSection(title: Briefing.title, isOpen: $sourcesOpen, spacing: 12) {
                Text(Briefing.intro)
                    .font(WindowType.item)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Briefing.items(for: state), id: \.source) { item in
                    row(item)
                }
                Text(Briefing.closing)
                    .font(WindowType.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(alignment: .firstTextBaseline) {
                // The only place this setting lives. It belongs to the moment the app is being
                // set up, and this window is reachable from the panel whenever it is wanted
                // again.
                LoginItemToggle(loginItem: .shared)
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

    /// The one mark this window hands over: the same title and the same line underneath, with
    /// the scale itself in place of the three dots — a picture of the marks that is also the
    /// way to move them.
    private func editableMarkRow(_ mark: MarkNote) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(mark.title)
                    .font(WindowType.item)
                Spacer()
                // Only on a mark that was actually moved: a button with nothing to undo is one
                // more control to read past, and this window is already a list of them.
                if limitChosen {
                    Button(Briefing.resetMark, action: resetLimitMarks)
                        .buttonStyle(.link)
                        .font(WindowType.detail)
                }
            }
            MarkScaleBar(title: mark.title, scale: $limitScale, settled: choose)
                // The title is the label of the bar, not a line of the bar: without the gap
                // the two read as one crowded block.
                .padding(.top, 4)
            // Nothing under a mark that was moved: what stood here explained a number that is
            // no longer there, and the Reset button beside the title is what says the mark is
            // the reader's own.
            if !limitChosen {
                Text(mark.note)
                    .font(WindowType.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(Briefing.markEditHint)
                .font(WindowType.detail)
                .foregroundStyle(.tertiary)
        }
    }

    /// Writes down a mark that has just been moved, keeping every other choice on disk: this
    /// window is not the only thing that will ever write to that file, and a choice is a choice
    /// about one mark rather than a snapshot of all of them.
    ///
    /// The panel is not redrawn here. It re-reads the marks on every pass of its own, and a
    /// menu bar that redrew itself on every step of a drag would be a second path to the same
    /// reading; what closing the window does instead is ask for one pass, once
    /// (`Welcome.marksChanged`).
    private func choose(_ scale: MarkScale) {
        limitChosen = true
        Welcome.marksChanged()
        let url = ThresholdChoicesStore.url()
        ThresholdChoicesStore.write(ThresholdChoicesStore.read(at: url).choosing(.limitUsage, scale), to: url)
    }

    /// Puts the limit marks back where the app had them, and takes the choice off the disk
    /// rather than writing the shipped numbers down as a choice of their own — the mark goes
    /// back to following the app, including through the releases that move it.
    private func resetLimitMarks() {
        limitScale = MarkScale(of: shipped.limitUsage)
        limitChosen = false
        Welcome.marksChanged()
        let url = ThresholdChoicesStore.url()
        ThresholdChoicesStore.write(ThresholdChoicesStore.read(at: url).forgetting(.limitUsage), to: url)
    }

    /// One mark: what it is, what it is set to, and who says so — with the source as a link
    /// when there is one, and an admission when there is not.
    private func markRow(_ mark: MarkNote) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text(mark.title)
                    .font(WindowType.item)
                Spacer()
                // A mark that is a scale shows the lights it actually turns on. Describing
                // them in a sentence asks the reader to match a colour to a number in their
                // head; a dot beside its percentage has already done it.
                if mark.scale.isEmpty {
                    Text(mark.value)
                        .font(WindowType.number)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        ForEach(mark.scale, id: \.percent) { step in
                            HStack(spacing: 4) {
                                StatusLight(light: .level(step.level), diameter: 7)
                                    .alignmentGuide(.firstTextBaseline) { $0.height * 0.5 + 2.5 }
                                Text(step.label)
                                    .font(WindowType.number)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Text(mark.note)
                    .font(WindowType.detail)
                    .foregroundStyle(.secondary)
                if let source = mark.source {
                    Link("source", destination: source)
                        .font(WindowType.detail)
                }
            }
        }
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

    private func row(_ item: BriefingItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: item.isConnected ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(item.isConnected ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(WindowType.item)
                Text(item.detail)
                    .font(WindowType.item)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
