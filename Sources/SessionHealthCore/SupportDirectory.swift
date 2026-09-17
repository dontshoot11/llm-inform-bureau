import Foundation

/// The directory this app keeps its own files in.
///
/// Four things live in it and nothing else does: the payloads the status line command leaves,
/// the command that held the slot before this app took it, the note that the first-run
/// explanation has been shown, and the marks the person moved for themselves
/// (`ThresholdChoicesStore`). The marks the app *watches by default* are not among them — those
/// ship inside the app, and what is kept here is a disagreement with one of them rather than a
/// copy of the lot.
///
/// `~/.codex` is never written to at all, and `~/.claude` only in one place: the
/// `statusLine.command` key of `settings.json`, which is the only way the subscription limits
/// can be seen on this machine. `StatusLineSlot` is what writes it, by the button in the panel
/// and never without showing the change first. Everything else the app keeps is here, where a
/// person can look at it and delete it.
public enum SupportDirectory {
    /// Points the whole directory somewhere else. For the tests and for a run against a
    /// working copy — the escape hatch `LLM_INFORM_BUREAU_THRESHOLDS` is for the config, and
    /// this is the same idea for everything around it.
    ///
    /// It exists because `$HOME` cannot do the job: `homeDirectoryForCurrentUser` asks the
    /// system for the account's home and ignores the variable, so a test that runs the built
    /// binary with a borrowed `HOME` would still write into the real Application Support.
    public static let environmentOverrideKey = "LLM_INFORM_BUREAU_SUPPORT"

    /// Where this app's own files go: the override if one is set, otherwise the usual place
    /// under this account's home.
    public static func url(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment[environmentOverrideKey], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return url(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// The same directory under a home named by the caller. Naming one means meaning it: the
    /// environment override is not consulted, so a test that points the app at a temporary
    /// home gets that home and nothing else.
    public static func url(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/LLMInformBureau", isDirectory: true)
    }
}
