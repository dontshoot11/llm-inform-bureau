import Foundation

/// The rule for a mark that is one number of minutes, as a person sets it: how small and how
/// large it may be, and what a typed number turns into.
///
/// A type of its own for the same reason `MarkScale` is one: the field that shows the number is
/// a view, and a view cannot be the place a rule lives. Three of these marks decide what the
/// panel lists and when it speaks (`ThresholdMark.minutes`), and every one of them arrives from
/// two directions — typed into the settings window, and read back off disk on the next launch.
/// Both meet the rule here rather than in two guards that can drift apart.
///
/// Usage:
/// ```swift
/// guard let minutes = MinuteMark.value(typed) else { return }   // refuse what is not a mark
/// field = MinuteMark.clamped(typed)                             // or walk it back into range
/// ```
public enum MinuteMark {
    /// What a number of minutes may be.
    ///
    /// Whole minutes, at least one: the app reads its sources in seconds but says these marks
    /// in minutes, and a mark under a minute is a number the interface cannot show the reader
    /// the way they set it. At most twelve hours, because past that these marks stop separating
    /// anything — a session nobody has written to since this morning is not one being worked
    /// on, and a wait that long is not one anybody is still expecting an answer out of. The
    /// ceiling is also what stops a slip of the hand (7200 for 720) from switching a mark off
    /// in a way nothing later would look wrong about.
    public static let allowed: ClosedRange<Int> = 1...720

    /// A mark, or `nil` for a number that is not one. The rule — the choice a person typed, and
    /// the record of it read back off disk, are refused here or nowhere.
    public static func value(_ minutes: Int) -> Int? {
        allowed.contains(minutes) ? minutes : nil
    }

    /// The nearest number this mark is allowed to be — what a field does with a number that
    /// has just been typed into it. Refusing it outright would leave the reader looking at
    /// their own figure with no sign of what the app did with it; the end of the range is
    /// where the mark visibly stops.
    public static func clamped(_ minutes: Int) -> Int {
        min(max(minutes, allowed.lowerBound), allowed.upperBound)
    }
}
