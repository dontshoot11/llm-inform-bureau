import AppKit
import ApplicationServices
import Foundation
import AgentFiles
import SessionHealthCore

/// Reads everything the checkup shows, without asking the system for anything.
///
/// The rule this whole file is written to: **opening the settings window must not raise a
/// permission dialog.** A dialog is a question, and the moment to ask one is when the person's
/// own click needs the answer — not when they opened a window to find out what the app is
/// doing. So accessibility is asked for with the plain `AXIsProcessTrusted()` rather than the
/// variant that carries a prompt, the notification centre is not touched at all (the checkup
/// reports whichever channel a notification has already gone out over), and everything else is
/// a file being read or a fact about this process.
///
/// It is also why this lives in the app rather than in `SessionHealthCore`: every line of it is
/// a border, and the list it produces is the part that is worth testing.
@MainActor
enum CheckupReader {
    static func read(
        sources: SetupState = SetupInspector.inspect(),
        slot: StatusLineSlotState = StatusLineSlot().state(),
        hasSessionRecords: Bool = ClaudeSessionRecordStore().hasAny(),
        notifications: NotificationChannel? = nil
    ) -> CheckupState {
        CheckupState(
            sources: sources,
            slot: slot,
            // The plain question, which answers out of the system's records. Its sibling —
            // the one that takes a prompt option — is what puts a dialog on screen, and it is
            // called in exactly one place, `TerminalRaiser`, after a click that needed the
            // answer. A test holds it to that one place, so naming the sibling here would be
            // this file failing it.
            isAccessibilityTrusted: AXIsProcessTrusted(),
            // Asked here rather than taken from the pass: the panel keeps no such fact, and a
            // listing bounded to one file is cheaper than a second way of remembering it.
            hasSessionRecords: hasSessionRecords,
            notifications: notifications,
            copy: runningCopy()
        )
    }

    /// Which bundle this is and when it was built.
    ///
    /// The date comes off the executable rather than out of `Info.plist`: the version keys do
    /// not move from build to build, and what has to be told apart here is two builds of the
    /// same version sitting on one disk. `ditto` preserves the date, which is what makes it
    /// survive the app being copied into `/Applications`.
    private static func runningCopy() -> RunningCopy {
        let bundle = Bundle.main.bundleURL
        let executable = Bundle.main.executableURL ?? bundle
        let built = try? FileManager.default
            .attributesOfItem(atPath: executable.path)[.modificationDate] as? Date
        return RunningCopy(path: bundle.path, builtAt: built ?? nil, isAdHoc: OwnSignature.isAdHoc)
    }
}

/// Opens a pane of System Settings.
///
/// The app opens it rather than describing where to click, for the reason the limits button
/// edits `settings.json` itself: a step written out in prose is a step half the people never
/// take. Which pane is which is `SystemSettingsPane`'s, under test; this is the one line that
/// hands it to the system.
@MainActor
enum SystemSettings {
    static func open(_ pane: SystemSettingsPane) {
        guard let url = pane.url else { return }
        NSWorkspace.shared.open(url)
    }
}
