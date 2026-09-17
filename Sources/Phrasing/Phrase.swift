import Foundation
import SessionHealthCore

/// Something the app says, in both of the languages it speaks.
///
/// A phrase is not a `String` with a translation table somewhere else — it is one value with two
/// sides, and there is no way to build one without writing both. That is the whole argument for
/// it over `.lproj` resources: an untranslated line does not compile, rather than passing every
/// test and reaching a reader as English in the middle of a Russian window.
///
/// Two more things came with that choice, and both matter in this codebase. The rationale stays
/// with the text — every string here carries a doc comment about what it may claim, and a
/// `.strings` file would leave those comments standing over a key with the words gone. And the
/// language can change while a window is open: nothing resolves a phrase until something draws
/// it, so switching the picker redraws the window rather than asking for a restart.
///
/// What the compiler cannot catch is a side left empty or two sides that are the same word in
/// both languages by accident. That is what the completeness test is for.
public struct Phrase: Equatable, Sendable, Hashable {
    public let english: String
    public let russian: String

    /// English first, always, because it is the side this project writes and reviews in — a
    /// pair whose order varied would make every call site a thing to check.
    public init(_ english: String, _ russian: String) {
        self.english = english
        self.russian = russian
    }

    public subscript(language: Language) -> String {
        switch language {
        case .english: english
        case .russian: russian
        }
    }

    /// The same phrase with something put on both sides.
    ///
    /// For the places where a phrase is built out of another one — a title with a unit after it,
    /// a sentence with a name in it. Written as a map over both sides rather than as two
    /// separate strings, so a builder cannot quietly forget the Russian half.
    public func mapped(_ transform: (String) -> String) -> Phrase {
        Phrase(transform(english), transform(russian))
    }
}
