import Foundation
import SessionHealthCore

/// What a source on disk had to say — three outcomes, not two.
///
/// "Nothing to show yet" and "the source stopped making sense" look the same in a widget that
/// only knows how to be empty, and they call for different reactions: one waits, the other
/// needs a look at the file format. Every reader here returns this shape, so the interface
/// treats all of them the same way and no source gets to be silently blank.
public enum SourceReading<Value: Equatable & Sendable>: Equatable, Sendable {
    /// The files answered.
    case value(Value)

    /// Nothing has been reported yet — no sessions, none that reached the API, or a source
    /// that has not been connected. The sentence says which, in words the panel can show.
    case noData(String)

    /// The files are there and no longer parse the way this app reads them.
    case unavailable(String)

    public var value: Value? {
        if case .value(let value) = self { return value }
        return nil
    }

    /// The sentence to show when there is no value. `nil` when there is one.
    public var explanation: String? {
        switch self {
        case .value: nil
        case .noData(let text), .unavailable(let text): text
        }
    }
}

/// The subscription limits of one service, or why they are not there.
public typealias LimitsReading = SourceReading<LimitsSnapshot>

/// The sessions of one service being worked on right now, or why the list is not there.
/// An empty list is a value, not an absence: it means "nothing is running", which is a fact.
public typealias SessionsReading = SourceReading<[SessionSnapshot]>
