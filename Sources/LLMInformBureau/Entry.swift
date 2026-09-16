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
        LLMInformBureauApp.main()
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
