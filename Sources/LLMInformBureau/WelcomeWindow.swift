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
    private static var watcher: WindowWatcher?

    /// The checkup this window is showing, kept so it can be read again while the window is
    /// open. Held here rather than by the view for the same reason the window is: a SwiftUI
    /// view is rebuilt at the system's convenience, and what it shows about this Mac has to
    /// outlive that.
    private static var live: LiveCheckup?

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

    /// Opens the window, or brings back the one that is already open.
    ///
    /// The checkup arrives as a way of reading it rather than as a reading, because this window
    /// outlives the answer: somebody opens it, finds a permission missing, goes and gives it,
    /// and comes back to the same window. What they come back to has to be read again
    /// (`LiveCheckup`), and only the caller knows how — the panel is where the slot and the
    /// notification channel are known.
    /// - Parameter point: the row of the checkup to bring the person to, when they were sent
    ///   here by something in the panel that could not do its job rather than by the gear. The
    ///   window is long and the answer is one line of it; scrolling to that line is the
    ///   difference between an explanation and a search.
    /// - Parameter slot: the way this window gives Claude Code's status line slot back, handed
    ///   over by whoever opened it. Absent on the first run, which happens before there is a
    ///   panel to ask and with nothing in the slot to give back anyway.
    static func show(
        checkup: @escaping @MainActor () -> CheckupState = { CheckupReader.read() },
        marks: ThresholdConfigLoad = ThresholdConfigLoader.load(),
        slot: SlotHandover? = nil,
        askForPass: (@MainActor () -> Void)? = nil,
        showing point: CheckupState.Point? = nil
    ) {
        // Remembered whenever it is offered rather than only on the first showing: the first
        // run opens this window before there is a panel to ask, and the gear that opens it
        // afterwards is the one that knows how.
        if let askForPass { Self.askForPass = askForPass }

        if let window {
            // Read afresh here as well as on the way back to the window: the panel has been
            // running all the while this window was closed, and the gear is the same gesture
            // as opening it the first time.
            live?.readAgain(with: checkup, handingBack: slot)
            if let point { live?.want(point) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let live = LiveCheckup(reading: checkup, handingBack: slot)
        // Asked for before the view is built, so the first layout already knows the checkup has
        // to be open: a section unfolding a moment after the window appears reads as the window
        // still loading.
        if let point { live.want(point) }
        Self.live = live

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = Briefing.windowTitle
        let content = NSHostingView(rootView: WelcomeView(live: live, marks: marks, close: close))
        window.contentView = content
        // Sized to what it actually holds — the marks come from the config and the list can
        // grow — but never taller than the screen it opens on.
        let wanted = content.fittingSize
        let room = (NSScreen.main?.visibleFrame.height ?? 800) - 80
        window.setContentSize(NSSize(width: wanted.width, height: min(wanted.height, room)))
        window.isReleasedWhenClosed = false
        window.center()
        Self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Watched from here on, and not before: coming to the front is what asks for the
        // checkup to be read again, and the window is coming to the front for the first time
        // on the line above — with a reading taken a moment ago, by whoever opened it.
        let watcher = WindowWatcher(
            cameBack: { live.readAgain() },
            closed: { finishedWithTheWindow() }
        )
        window.delegate = watcher
        Self.watcher = watcher
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
        // Before anything else, and whether a mark moved or not: a question about somebody's
        // settings.json expires with the window it was asked in, the way the panel's questions
        // expire when the panel closes.
        live?.windowClosed()
        guard marksMoved else { return }
        marksMoved = false
        askForPass?()
    }
}

/// The way out of Claude Code's status line slot, as the settings window is given it.
///
/// Both halves belong to the panel — it owns the one `StatusLineSlot` this app writes through,
/// and it is what re-reads the file afterwards — so the window is handed them rather than
/// reaching for the slot itself. A window reading and writing that file on its own is how two
/// parts of one app come to disagree about what is in it.
@MainActor
struct SlotHandover {
    /// What the change would be, before anything is written. `nil` when there is nothing to
    /// give back: the file already looks the way this would leave it.
    let plan: () -> StatusLineChange?

    /// Writes the change that was shown, and answers with what went wrong, or `nil`. It does
    /// not return until the panel has read the file again, so the row that asked can then read
    /// it too and show what is really there.
    let write: (StatusLineChange) async -> String?
}

/// Tells `Welcome` the two things that happen to its window from outside: it came back to the
/// front, and it closed. A window's delegate is a weak reference and an enum cannot be one, so
/// this exists to be held.
@MainActor
private final class WindowWatcher: NSObject, NSWindowDelegate {
    private let cameBack: () -> Void
    private let closed: () -> Void

    init(cameBack: @escaping () -> Void, closed: @escaping () -> Void) {
        self.cameBack = cameBack
        self.closed = closed
    }

    func windowDidBecomeKey(_ notification: Notification) {
        cameBack()
    }

    func windowWillClose(_ notification: Notification) {
        closed()
    }
}

/// The checkup as the open window shows it, read again whenever the window comes back to the
/// front.
///
/// The one thing in this window that belongs to the machine rather than to the person. They
/// read a row, leave for System Settings, give the permission and come back — and a row still
/// saying "not given" would be the app arguing with what they had just done. Coming back is
/// both the moment it is worth looking again and the only moment it is worth anything: nobody
/// gives a permission to a window they are looking at.
///
/// So no timer. Every state here is a directory listing, a small file or a question about this
/// process — cheap once, and a waste every thirty seconds of a window nobody has touched. The
/// same conclusion the panel came to about its own reading, for the same reason
/// (`TODO/archive/refresh-cost`), and measured here too: a re-read costs a fraction of a pass.
@MainActor
final class LiveCheckup: ObservableObject {
    @Published private(set) var state: CheckupState

    /// The row somebody was sent here to read, and which journey sent them.
    ///
    /// A count beside the row and not the row alone: the same dead end pressed twice is two
    /// journeys, and the second one has to bring the window back to a row the person has since
    /// scrolled away from. Without it the second press would change nothing and read as the
    /// panel having ignored the click.
    struct WantedRow: Equatable {
        let point: CheckupState.Point
        let journey: Int
    }

    @Published private(set) var wanted: WantedRow?

    /// How many times this window has been closed. What a question asked in it watches, so that
    /// reopening the window does not find a half-pressed decision from an hour ago — a counter
    /// rather than a flag, because a flag that is already set says nothing the second time.
    @Published private(set) var closings = 0

    func windowClosed() {
        closings += 1
    }

    /// Sends whoever opens this window to one row of the checkup.
    func want(_ point: CheckupState.Point) {
        wanted = WantedRow(point: point, journey: (wanted?.journey ?? 0) + 1)
    }

    /// How to read the machine again. Kept rather than called once, and replaced when the
    /// window is opened afresh, because the reading belongs to whoever opened this window: the
    /// slot and the notification channel are the panel's own knowledge, and reading them here
    /// as well is how two parts of one app come to disagree about the same fact.
    private var reading: @MainActor () -> CheckupState

    /// How to give the slot back, from whoever opened this window — kept beside the reading for
    /// the same reason, and replaced with it: the panel that reads the slot is the panel that
    /// writes it.
    @Published private(set) var handingBack: SlotHandover?

    init(reading: @escaping @MainActor () -> CheckupState, handingBack: SlotHandover? = nil) {
        self.reading = reading
        self.handingBack = handingBack
        self.state = reading()
    }

    func readAgain(
        with reading: (@MainActor () -> CheckupState)? = nil,
        handingBack: SlotHandover? = nil
    ) {
        if let reading { self.reading = reading }
        if let handingBack { self.handingBack = handingBack }
        state = self.reading()
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
    /// Everything this Mac has given the app, and what it has not — watched rather than held,
    /// because it changes under the open window: the person is out giving a permission.
    @ObservedObject var live: LiveCheckup

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

    init(live: LiveCheckup, marks: ThresholdConfigLoad, close: @escaping () -> Void) {
        self.live = live
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
        // Off the reading the window opened with. It is not re-decided when the list is read
        // again: a section folding itself away under somebody who has just given a permission
        // would take away the row they came back to look at.
        // Open for a person who was sent to a row in it, whatever the machine says: they were
        // sent there to read that line.
        _checkupOpen = State(initialValue: live.wanted != nil || live.state.hasSomethingMissing)
    }

    /// The row the window was opened on, while the mark that says which one is still showing.
    ///
    /// Scrolling alone is not an answer: the row it stops at is one of ten that look alike, and
    /// a person who arrived from a click needs to be told which line was the point. It fades by
    /// itself, because after a few seconds it is no longer news and a window that stays marked
    /// is a window with a stuck highlight in it.
    @State private var arrivedAt: LiveCheckup.WantedRow?

    /// The edit that gives the status line slot back, while it is on screen waiting to be
    /// agreed to. Nothing is written until it is.
    @State private var handingBack: StatusLineChange?

    /// What went wrong the last time this window wrote to `settings.json`, and nothing while it
    /// worked: the line above already says what is in the slot now.
    @State private var slotProblem: String?

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                content
            }
            // Both, and for two different arrivals: a window built for this journey has its row
            // waiting before it appears, and a window already open is told about the next one.
            .onAppear { go(to: live.wanted, with: scroll) }
            .onChange(of: live.wanted) { go(to: $0, with: scroll) }
            // A question about somebody's settings.json does not outlive the window it was
            // asked in, and neither does the answer to the last one: reopening this window is
            // somebody coming to look, not coming back to a decision from an hour ago.
            .onChange(of: live.closings) { _ in
                handingBack = nil
                slotProblem = nil
            }
        }
        .frame(width: 460)
    }

    /// Brings the window to the row somebody was sent to.
    private func go(to wanted: LiveCheckup.WantedRow?, with scroll: ScrollViewProxy) {
        guard let wanted else { return }
        checkupOpen = true
        arrivedAt = wanted
        // The rows of a folded section are not in the view tree to scroll to yet: unfolding it
        // is a change SwiftUI applies when this run loop is over, and a scroll asked for before
        // then lands on whatever was there instead.
        DispatchQueue.main.async {
            withAnimation { scroll.scrollTo(wanted.point, anchor: .center) }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            // Compared whole, journey and all: a second click on the same dead end while this
            // one is still counting down must not have its mark taken away by the first.
            guard arrivedAt == wanted else { return }
            withAnimation { arrivedAt = nil }
        }
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
                ForEach(CheckupPhrasing.rows(for: live.state), id: \.point) { row in
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
            // What the mark decides stands under every one of them, moved or not: it describes
            // the mark rather than the number on it, and somebody who has just dragged a handle
            // is the reader who most needs it. Under it, where the number itself came from —
            // which is the half a moved mark takes with it, because what shipped here was
            // written about the app's number and not about theirs.
            Text(mark.what)
                .font(WindowType.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !mark.origin.isEmpty {
                HStack(spacing: 6) {
                    Text(mark.origin)
                        .font(WindowType.detail)
                        .foregroundStyle(.tertiary)
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
        let arrived = arrivedAt?.point == row.point
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
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
                // The second row of this list to carry a control of its own, after the login
                // checkbox — and, like that one, it stands where the row's answer is: this is
                // the line that says what is in the slot, and a control that takes a reading
                // away belongs beside the sentence explaining the reading rather than under the
                // number it would take away.
                if row.point == .statusLineSlot { slotHandover }
                // Under the sentence rather than in place of the title, which is where the
                // login checkbox stands: that row is nothing but its checkbox, and this one has
                // an answer of its own above — whose name a banner arrives under, which is the
                // machine's to give and not anybody's to tick.
                if row.point == .notifications { NotificationToggle() }
            }
        }
        // What a person sent here from the panel is looking for. Taken back off the outside so
        // that a marked row keeps its place in the column with the rest of them.
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(arrived ? 0.15 : 0))
        )
        .padding(-6)
        // The anchor a journey scrolls to. On the row rather than on the section: the section
        // is most of the window by the time it is open, and stopping at its top leaves the line
        // that was the point somewhere below the fold.
        .id(row.point)
    }

    /// The way back out of Claude Code's status line slot, under the line that says the app is
    /// in it.
    ///
    /// It used to be an icon at the foot of the panel, and it is here now for the reason the
    /// rest of this window exists: it is a setting, not a reading. The panel is a page of
    /// numbers read at a glance, and a control that takes one of those numbers away — by
    /// editing somebody's `settings.json` — is something a person goes looking for once, in the
    /// place where the app says what it uses on this Mac.
    ///
    /// Only while the slot holds this copy's own command, which is the only thing this app ever
    /// takes out of it: another copy's command and somebody else's alike are given back by
    /// nothing here.
    @ViewBuilder
    private var slotHandover: some View {
        if let handover = live.handingBack, live.state.slot.isOurs {
            if let change = handingBack {
                handoverPreview(change, write: handover.write)
            } else {
                Button(SlotPhrasing.disconnect) {
                    slotProblem = nil
                    handingBack = handover.plan()
                    // Nothing to give back means the file has moved on under this window —
                    // edited by hand, or taken by another copy of the app. Reading it again is
                    // the answer; a preview of nothing would be the window arguing with the
                    // file.
                    if handingBack == nil { live.readAgain() }
                }
                .buttonStyle(.link)
                .font(WindowType.detail)
                .help(SlotPhrasing.disconnectHelp)
            }
        }
        if let slotProblem {
            Text(slotProblem)
                .font(WindowType.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The edit to `settings.json`, before it is made: the file, the line that will be in the
    /// slot afterwards, and what that does to what is there now. Then the two answers.
    ///
    /// The same sentences the panel shows before it connects (`SlotPhrasing.preview`), set in
    /// this window's type: one question about somebody's file, asked the same way wherever it
    /// is asked.
    private func handoverPreview(
        _ change: StatusLineChange,
        write: @escaping (StatusLineChange) async -> String?
    ) -> some View {
        let preview = SlotPhrasing.preview(change)

        return VStack(alignment: .leading, spacing: 6) {
            Text(preview.title)
                .font(WindowType.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(preview.path)
                .font(WindowType.detail.monospaced())
                .fixedSize(horizontal: false, vertical: true)
            if let command = preview.command {
                Text(command)
                    .font(WindowType.detail.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(preview.notes, id: \.self) { note in
                Text(note)
                    .font(WindowType.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Both answers on screen, for the reason the panel has both: a question with one
            // button leaves saying no to guesswork about where to click.
            HStack {
                // Return is Done's in this window, and it stays Done's: the key somebody
                // presses without reading must be the one that closes the window with nothing
                // written. Escape means no, which is the other half of the same care.
                Button(SlotPhrasing.apply) {
                    handingBack = nil
                    Task {
                        slotProblem = await write(change)
                        // The panel has read the file again by now; this reads what it found,
                        // so the line above says what is in the slot rather than what this
                        // window asked for.
                        live.readAgain()
                    }
                }
                Button(SlotPhrasing.cancel) { handingBack = nil }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.top, 2)
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
