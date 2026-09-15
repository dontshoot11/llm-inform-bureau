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

    /// Shows the explanation the first time the app runs, and records that it did.
    static func showIfDue(record: WelcomeRecord = WelcomeRecord()) {
        guard !record.hasBeenShown else { return }
        record.markShown()
        show()
    }

    static func show(
        state: SetupState = SetupInspector.inspect(),
        config: ThresholdConfig = ThresholdConfigLoader.load().config
    ) {
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
        window.title = Briefing.title
        let content = NSHostingView(rootView: WelcomeView(state: state, config: config, close: close))
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
    }

    private static func close() {
        window?.close()
    }
}

/// What the first run says, in the order it matters: how the app gets its numbers, then each
/// source with whether it is connected, then what an unconnected source looks like in the
/// panel.
private struct WelcomeView: View {
    let state: SetupState
    let config: ThresholdConfig
    let close: () -> Void

    var body: some View {
        ScrollView {
            content
        }
        .frame(width: 460)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Briefing.title)
                .font(.title3.weight(.semibold))
            Text(Briefing.intro)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Briefing.items(for: state), id: \.source) { item in
                    row(item)
                }
            }

            Text(Briefing.closing)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // Read out of the config, so this list cannot claim a number the app does not use.
            Text(Briefing.marksTitle)
                .font(.callout.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Briefing.marks(of: config), id: \.title) { mark in
                    markRow(mark)
                }
            }
            Text(Briefing.marksNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Text(Briefing.furtherReadingTitle)
                .font(.callout.weight(.semibold))
            Text(Briefing.furtherReadingNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Briefing.furtherReading, id: \.title) { reading in
                    readingRow(reading)
                }
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
    }

    /// One mark: what it is, what it is set to, and who says so — with the source as a link
    /// when there is one, and an admission when there is not.
    private func markRow(_ mark: MarkNote) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline) {
                Text(mark.title)
                    .font(.callout)
                Spacer()
                // A mark that is a scale shows the lights it actually turns on. Describing
                // them in a sentence asks the reader to match a colour to a number in their
                // head; a dot beside its percentage has already done it.
                if mark.scale.isEmpty {
                    Text(mark.value)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        ForEach(mark.scale, id: \.percent) { step in
                            HStack(spacing: 4) {
                                StatusLight(light: .level(step.level), diameter: 7)
                                    .alignmentGuide(.firstTextBaseline) { $0.height * 0.5 + 2.5 }
                                Text(step.label)
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Text(mark.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let source = mark.source {
                    Link("source", destination: source)
                        .font(.caption)
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
                        .font(.callout)
                } else {
                    Text(reading.title)
                        .font(.callout)
                }
                Text(reading.year)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(reading.note)
                .font(.caption)
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
                    .font(.callout.weight(.medium))
                Text(item.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
