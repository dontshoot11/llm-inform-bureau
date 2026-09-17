import Foundation

/// Whether the app may say anything out loud, as the person left it.
///
/// The one decision about notifications that is nobody's but theirs. Everything else on that
/// line of the checkup belongs to the machine — whether the notification centre will take this
/// copy at all, and whose name a banner arrives under — and none of it is a choice: the app
/// finds out by sending one. "Say something, or keep quiet" is the other kind of question, and
/// until now there was nothing to answer it with.
///
/// A file whose being there *is* the choice, rather than a setting with a value in it. Silence
/// is the rarer answer and the only one worth recording: somebody who never opened the window
/// leaves nothing on this disk at all, and the app they get is the app as it shipped. It sits
/// beside the note that the first run has been explained (`WelcomeRecord`) and the marks that
/// were moved (`ThresholdChoicesStore`), for the same reason as both — a file a person can
/// look at, and delete when they want the app to speak again.
///
/// It is not a mark, and the rules that guard the marks do not reach it: there is no order to
/// keep and no range to fall outside of, so a file that is there means quiet and a file that
/// is not means the app speaks. Whatever is written inside it is a note to whoever opens it.
///
/// Nothing here throws. A choice that cannot be read is no choice, and the app goes on saying
/// what it would have said — the same fallback as the rest of this module, and the right one:
/// the failure a person can see and act on is an app that stayed quiet, not one that spoke.
public enum NotificationChoice {
    /// Named after the state it records rather than after the app's own vocabulary: somebody
    /// looking through this directory for the reason their Mac stopped saying anything reads
    /// the file name and knows.
    public static let fileName = "notifications-off"

    public static func url(in directory: URL = SupportDirectory.url()) -> URL {
        directory.appendingPathComponent(fileName, isDirectory: false)
    }

    /// Whether the app has been asked to keep quiet.
    ///
    /// Asked of the disk every time rather than remembered: the window writes this file while
    /// the app is running, and a remembered answer the file disagrees with is how a control
    /// like this starts lying (`LoginItem` came to the same conclusion about the system's own
    /// answer).
    public static func isSilenced(at url: URL = url()) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Writes the choice down, or takes it back by removing the file — so switching the
    /// notifications on again leaves nothing behind to be found by a later release.
    ///
    /// `false` when the disk refused, which costs the person the choice they just made and
    /// nothing else; the app goes on as it was.
    @discardableResult
    public static func silence(
        _ wanted: Bool,
        at url: URL = url(),
        on moment: Date = Date()
    ) -> Bool {
        let manager = FileManager.default
        guard wanted else {
            if !manager.fileExists(atPath: url.path) { return true }
            return (try? manager.removeItem(at: url)) != nil
        }

        try? manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A date and a sentence, because the file is read by people and not by this app: what
        // it says is why their Mac has gone quiet and how to undo it. The app asks only
        // whether it is there.
        let note = """
            \(ISO8601DateFormatter().string(from: moment))
            Notifications were switched off in this app's settings window. Delete this file, or \
            tick the box again, and it starts announcing crossed marks as before.

            """
        return (try? Data(note.utf8).write(to: url, options: .atomic)) != nil
    }
}
