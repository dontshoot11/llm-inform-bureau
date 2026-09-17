import Foundation
import Phrasing
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
    case noData(Phrase)

    /// The files are there and no longer parse the way this app reads them.
    case unavailable(Phrase)

    public var value: Value? {
        if case .value(let value) = self { return value }
        return nil
    }

    /// The sentence to show when there is no value. `nil` when there is one.
    ///
    /// A phrase and not a string, because this sentence is shown: it stands in the panel where
    /// a number would have been, and a reading that came to nothing is the commonest thing
    /// this app has to say. Which side of it a reader sees is decided where it is drawn.
    public var explanation: Phrase? {
        switch self {
        case .value: nil
        case .noData(let text), .unavailable(let text): text
        }
    }
}

/// What a reader says about one file it has just walked, in the words every reader uses.
///
/// Three sentences about a file rather than about a service: they read the same whichever
/// agent's transcripts are being walked, and a copy of each per reader is how two halves of
/// one panel come to say the same thing in two ways.
public enum FileSaid {
    /// The file would not open at this moment. Not a verdict on it: the next pass asks again.
    public static let couldNotOpen = Phrase(
        "could not be opened just now",
        "не удалось открыть прямо сейчас"
    )

    /// The file opened and carries no answer yet — a session that has been started and not
    /// yet worked in.
    public static let nothingAnsweredYet = Phrase("nothing answered yet", "ответов пока нет")

    /// The file opened, its lines are there, and they are not the shape this app reads.
    public static let unreadableLines = Phrase("unreadable lines", "строки не читаются")
}

/// The subscription limits of one service, or why they are not there.
public typealias LimitsReading = SourceReading<LimitsSnapshot>

/// The sessions of one service being worked on right now, or why the list is not there.
/// An empty list is a value, not an absence: it means "nothing is running", which is a fact.
public typealias SessionsReading = SourceReading<[SessionSnapshot]>
