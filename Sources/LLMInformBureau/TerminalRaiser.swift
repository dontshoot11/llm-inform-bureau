import AppKit
import AgentFiles
import Foundation
import SessionHealthCore

/// Takes a person to the window their session is running in.
///
/// The other end of everything this app does. Every reading here ends in the same place — the
/// terminal where the agent is waiting — and until now a person got there by looking through
/// a dozen windows for the one they had just been told about. A click on the row is the whole
/// feature; this is what the click does.
///
/// **What it may do without asking.** Finding the application above a process is reading the
/// process table, and bringing it forward is `NSRunningApplication.activate()` — neither needs
/// permission from anybody, and that is what makes raising the application the floor rather
/// than a consolation. Only the tab needs more: asking Terminal.app or iTerm2 which of their
/// tabs holds a terminal device is an Apple event, and the system asks the person about that
/// the first time it happens. It asks because of *their* click, which is the one moment where
/// a permission dialog explains itself.
///
/// **A refusal is not an error.** Whatever goes wrong with the tab — permission refused, a
/// terminal that turned out not to answer, a tab that has since closed — the fallback is the
/// application, which was always the floor. The one thing a refusal changes is that the panel
/// then has something to offer: the pane of System Settings where that answer is kept
/// (`Wording.automationOffer`), opened by the app rather than described to the person.
///
/// Like `Notifier`, this runs `osascript` as a subprocess instead of sending Apple events
/// itself: it is the same border with the same tool, and an ad-hoc-signed app sending its own
/// events is a different conversation with the system than this app has ever had.
@MainActor
final class TerminalRaiser {
    /// What a click actually got the person.
    enum Outcome: Equatable {
        /// Their tab is in front of them.
        case tab
        /// Their window is in front of them, picked out of the application's others.
        case window
        /// The application is in front of them, which is everything this terminal can give.
        case app
        /// The application was raised, and the closer answer was not available because the
        /// system has not been told it may give it. The panel may now offer that pane.
        case appWithout(TerminalRaise.Permission)
        /// Nothing was raised: the process is gone, or nothing owns it.
        case nothing
    }

    /// Raises what can be raised for this process.
    ///
    /// Asynchronous because of the one slow step: `osascript` walks the terminal's windows,
    /// and on the first ever call it waits for a person to answer a permission dialog. A panel
    /// frozen until they do would look like the click had broken it.
    func raise(processID pid: Int32, project: String?) async -> Outcome {
        guard let owner = Self.owningApplication(of: pid) else { return .nothing }
        let plan = TerminalRaise.plan(
            owner: owner.bundleIdentifier,
            tty: SessionProcess.terminalName(pid),
            project: project
        )

        switch plan {
        case .nothing:
            return .nothing
        case .app:
            Self.bringForward(owner)
            return .app
        case .window(let title):
            // The window first and the application second, so that what comes to the front is
            // the one that was raised rather than whichever was last used.
            switch Self.raiseWindow(of: owner, titled: title) {
            case .raised:
                Self.bringForward(owner)
                return .window
            case .noMatch:
                Self.bringForward(owner)
                return .app
            case .notAllowed:
                Self.bringForward(owner)
                return .appWithout(.accessibility)
            }
        case .tab(let script):
            let raised = await Self.run(script)
            // The script's own answer, not merely its exit code: a tab that has since closed
            // leaves a terminal that answered perfectly well and found nothing, and that is
            // not something to offer a person settings about.
            switch raised {
            case .raised:
                return .tab
            case .answeredNoTab:
                Self.bringForward(owner)
                return .app
            case .failed:
                Self.bringForward(owner)
                return .appWithout(.automation)
            }
        }
    }

    /// Opens the pane of System Settings where this answer is kept.
    ///
    /// The app does this itself rather than telling a person where to click, for the reason
    /// the limits button installs the status line itself: a step described in prose is a step
    /// half of the people never take.
    static func openSettings(for permission: TerminalRaise.Permission) {
        SystemSettings.open(permission.pane)
    }

    // MARK: The border itself

    /// The application that started this process: the first one above it the system calls an
    /// application at all.
    ///
    /// The chain and not the parent, and the first *application* rather than the first
    /// plausible name — measured on this machine, a session in the terminal of VS Code has
    /// `Code Helper` above it, which is a process the system does not consider an application,
    /// with the application one step further up again.
    private static func owningApplication(of pid: Int32) -> NSRunningApplication? {
        for step in SessionProcess.ancestors(of: pid) {
            if let app = NSRunningApplication(processIdentifier: step) { return app }
        }
        return nil
    }

    private enum WindowResult {
        case raised
        case noMatch
        case notAllowed
    }

    /// Whether the system's dialog about assistive access has been put up in this run.
    ///
    /// Per run rather than remembered on disk: a person who gave the access, or took it away,
    /// did it in a pane this app does not watch, and a launch is the one moment where asking
    /// again costs nothing and might be the truth.
    private static var askedForAccessibility = false

    /// Raises the window of this application whose title carries `title`.
    ///
    /// **Why a title.** Nothing else about a window says which session is in it. A terminal
    /// device belongs to a tab, and the applications that reach this point are the ones with
    /// no notion of a tab to ask about; what they do have is a window titled after the folder
    /// open in it — `MenuContent.swift — llm-inform-bureau` — and the panel knows that folder's
    /// name because it is the project on the session's row. A match is not proof, and it does
    /// not have to be: the worst a wrong one can do is raise a window of the same project.
    ///
    /// **Why it can be refused.** Reading another application's windows is assistive access,
    /// which a person gives by hand in Privacy & Security → Accessibility. This asks for it at
    /// the moment of a click and never before, with the system's own dialog, and then carries
    /// on without it — measured, an attempt without it comes back "not allowed assistive
    /// access" rather than empty, which is why a refusal is told apart from an application
    /// whose windows simply do not match.
    ///
    /// **Why the dialog is counted.** The system does not remember that it asked: while access
    /// is missing, every call that carries the prompt puts the dialog up again, so a person
    /// who has not given it got one per click — reported, and the reason this counts its own
    /// asking. Past the first, the panel's own line is what offers the pane, and it survives
    /// the panel closing no worse than a dialog does.
    private static func raiseWindow(of app: NSRunningApplication, titled title: String) -> WindowResult {
        // Asked without the prompt first: this is the question, and the dialog is a separate
        // decision below.
        guard AXIsProcessTrusted() else {
            // The prompt is part of the click: a person who has just asked to be taken
            // somewhere is the one person for whom a permission dialog needs no explaining.
            // Once, though — see above.
            // The key by its own name rather than through `kAXTrustedCheckOptionPrompt`: that
            // constant is a global `var` in the C header, which Swift 6 will not let a
            // concurrent program read. Its value is this string, and has been since the option
            // existed.
            if !askedForAccessibility {
                askedForAccessibility = true
                let prompt = "AXTrustedCheckOptionPrompt" as CFString
                _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
            }
            return .notAllowed
        }

        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
        guard status == .success, let windows = value as? [AXUIElement] else {
            // `.apiDisabled` and `.notImplemented` are the shapes a refusal takes here; every
            // other failure is an application that cannot be asked, and both end the same way
            // — the application raised, and the panel free to mention the pane.
            return status == .success ? .noMatch : .notAllowed
        }

        for window in windows {
            var titleValue: CFTypeRef?
            guard
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
                let found = titleValue as? String,
                found.localizedCaseInsensitiveContains(title)
            else { continue }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            return .raised
        }
        return .noMatch
    }

    private static func bringForward(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private enum ScriptResult {
        case raised
        case answeredNoTab
        case failed
    }

    /// Runs one AppleScript and reads what it said.
    ///
    /// Off the main actor, because this is the step that can wait on a person. Everything it
    /// touches is a local value, and the answer it brings back is a word.
    private static func run(_ script: String) async -> ScriptResult {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let output = Pipe()
            process.standardOutput = output
            // Whatever osascript complains about is its own business: the exit code is what
            // this reads, and the complaint would only end up in a log nobody opens.
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                return .failed
            }
            let said = String(
                data: output.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return .failed }
            return said.contains("raised") ? .raised : .answeredNoTab
        }.value
    }
}
