import AppKit
import Foundation
import AgentFiles
import Phrasing

/// Where the process starts, and the one fork in it.
///
/// The same binary is two things. Double-clicked, it is the menu bar app. Run with
/// `--status-line`, it is the command Claude Code calls after every answer — the only way the
/// subscription limits and the size of the context window can be seen on this machine at all.
///
/// The fork has to happen here, before `App.main()`, because that call never comes back: it
/// starts AppKit, puts an item in the menu bar and runs the event loop. The status line mode
/// reaches none of that, which is the point — it is a program that reads stdin, prints a line
/// and exits, and it runs after every answer the assistant gives.
///
/// `@main` lives on this type rather than on the scene for the same reason. A `main.swift`
/// would have done the same job and cannot be used: a file by that name and a `@main` type
/// cannot both be in one target.
@main
enum Entry {
    static func main() {
        if CommandLine.arguments.dropFirst().contains(StatusLineMode.argument) {
            exit(printStatusLine())
        }
        endOtherCopies()
        LLMInformBureauApp.main()
    }

    /// Leaves exactly one menu bar item behind: this one.
    ///
    /// Two copies of this app are easy to end up with — a build beside an installed bundle, an
    /// app dragged to a new place, a login item starting one while another is already up — and
    /// two copies are not a cosmetic problem. They put two identical lights in the bar, say
    /// every notification twice, and offer the status line slot from two panels that disagree
    /// about who holds it. Nothing on screen says which copy is which.
    ///
    /// The copy that starts last wins, deliberately: launching an app is how a person asks for
    /// it, and a newly built or newly installed bundle is the one they mean. The others are
    /// asked to quit the ordinary way — they are the same app and have nothing unsaved — and
    /// this one waits a moment so the bar is not briefly showing both.
    ///
    /// Only the menu bar app does this. The status line mode is a command that Claude Code may
    /// run at any moment, several at once, and it exits on its own.
    private static func endOtherCopies() {
        guard let identifier = Bundle.main.bundleIdentifier else { return }
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != mine }
        guard !others.isEmpty else { return }

        for copy in others {
            copy.terminate()
        }
        // A short wait, not a guarantee: a copy that will not go is left alone rather than
        // killed. Whatever is holding it up, ending it by force is not this app's call.
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, others.contains(where: { !$0.isTerminated }) {
            usleep(50_000)
        }
    }

    /// Reads the payload, saves it, and prints whatever the status line should say.
    ///
    /// Always zero: Claude Code runs this after every answer, and an exit code it did not
    /// expect is a complaint at the bottom of the terminal on every turn. There is no failure
    /// here worth that — everything this mode does is either done or quietly not done.
    private static func printStatusLine() -> Int32 {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        switch StatusLineMode().run(input: input) {
        case .passedThrough(let output):
            FileHandle.standardOutput.write(output)
        case .nothingToPassTo(let reading):
            print(
                StatusLineText.line(
                    model: reading.model,
                    contextTokens: reading.contextTokens,
                    contextWindowTokens: reading.contextWindowTokens,
                    limits: reading.limits
                )
            )
        }
        return 0
    }
}
