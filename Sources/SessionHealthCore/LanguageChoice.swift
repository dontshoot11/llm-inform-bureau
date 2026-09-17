import Foundation

/// The two languages this app's interface is written in.
///
/// Named here, beside the file that records which one somebody picked, and nowhere else: this
/// module holds *which* language, never what is said in it. The sentences live in `Phrasing`,
/// which is where the rule that a rule never reads English keeps its edge — a case of this enum
/// carries no English and no Russian, only a name for a side of every phrase.
///
/// Two cases and not an open list. A third language is not a case away: it is a third side on
/// every phrase in `Phrasing`, and the compiler is what would say so.
public enum Language: String, CaseIterable, Sendable {
    /// The language the project is written in — the README, the code, and the side of every
    /// phrase written first.
    case english = "en"
    case russian = "ru"
}

/// The language the person picked for themselves, as it survives a restart.
///
/// A file beside the marks they moved (`ThresholdChoicesStore`) and the file that records a
/// request to keep quiet, for the reason both of those are there: it outlives a new copy
/// dragged over the old one, and it is a thing somebody can look at and delete. What is in it
/// is one line — the code of the language — and under that a note for whoever opens it.
///
/// **Not having chosen is not the same as having chosen English**, and this is where the
/// difference is kept: no file means the app follows the Mac, so somebody who never opened the
/// window and then switches their system to Russian gets a Russian app. A file means they said
/// which one, and the system no longer has a vote. The difference is the file being there
/// rather than a value inside it, which is the only way it cannot be lost by somebody editing
/// the contents.
///
/// A string and not JSON. `ThresholdChoicesStore` carries a format version because a record
/// there can come to mean something else; one language code cannot, and a version to check
/// would be a moving part with nothing behind it.
///
/// Nothing here throws. An unreadable file, an empty one, a code from a release that spoke
/// three languages — each of them is "nobody chose", and the app goes to the Mac for an answer
/// the way it does on a machine where this file was never written.
public enum LanguageChoice {
    /// Named after what it holds rather than after the app's vocabulary, so that somebody going
    /// through this directory to find out why their app changed language reads the file name
    /// and knows.
    public static let fileName = "chosen-language"

    public static func url(in directory: URL = SupportDirectory.url()) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// The language somebody picked, or `nil` when nobody has.
    ///
    /// Asked of the disk rather than remembered, for the reason the other choices in this
    /// directory are asked for every time: the file is written while the app runs and can be
    /// deleted by hand, and a remembered answer the disk disagrees with is how a control starts
    /// lying about itself.
    public static func chosen(at url: URL = url()) -> Language? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // The first line is the answer and everything under it is the note. Trimmed because a
        // file somebody opened in an editor comes back with whitespace that means nothing.
        let code = contents
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .trimmingCharacters(in: .whitespaces)
        return Language(rawValue: code)
    }

    /// Writes the choice down, or takes it back with `nil` — which removes the file, so an app
    /// put back to following the Mac leaves nothing behind for a later release to read.
    ///
    /// `false` when the disk refused. That costs the person the choice they just made and
    /// nothing else: the language on screen is the one they picked until the app is restarted,
    /// and the restart brings back the one before it.
    @discardableResult
    public static func choose(
        _ language: Language?,
        at url: URL = url(),
        on moment: Date = Date()
    ) -> Bool {
        let manager = FileManager.default
        guard let language else {
            if !manager.fileExists(atPath: url.path) { return true }
            return (try? manager.removeItem(at: url)) != nil
        }

        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // The code first, alone on its line, because that is the part the app reads. The rest is
        // written for whoever opens the file: what it does and how to undo it.
        let note = """
            \(language.rawValue)
            \(ISO8601DateFormatter().string(from: moment))
            The interface language was picked in this app's settings window. Delete this file \
            and the app goes back to following the language of this Mac.

            """
        return (try? Data(note.utf8).write(to: url, options: .atomic)) != nil
    }
}
