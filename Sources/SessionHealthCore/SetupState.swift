import Foundation

/// Which of the app's sources have anything to say on this machine.
///
/// The widget reads three sources, and they are not alike: two are simply there once the CLI
/// has been run, and one has to be installed by hand. A widget that shows an em dash and
/// explains nothing looks broken when it is merely not connected yet — so this is what the
/// first run explains, and what the panel keeps saying while something is missing.
///
/// Facts only: the English is `Phrasing`'s, and reading the disk is `AgentFiles`'.
public struct SetupState: Equatable, Sendable {
    /// The sources, named by what they give rather than by the file they come from.
    public enum Source: String, CaseIterable, Sendable {
        /// Claude's subscription limits and the size of its context window, from the
        /// status line. The one source a person has to connect.
        case claudeLimits
        /// Claude's context budget, from the transcripts.
        case claudeSessions
        /// Codex limits and context both, from the rollouts.
        case codex
    }

    /// The sources that have left something this app can read.
    public let connected: Set<Source>

    public init(connected: Set<Source>) {
        self.connected = connected
    }

    public func isConnected(_ source: Source) -> Bool { connected.contains(source) }

    /// Whether anything is still waiting to be connected — which is what decides whether the
    /// panel carries the explanation at all.
    public var isComplete: Bool { connected.count == Source.allCases.count }
}
