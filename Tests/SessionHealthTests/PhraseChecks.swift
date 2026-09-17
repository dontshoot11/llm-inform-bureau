import Foundation
import Phrasing

/// Checking a phrase, where the question is nearly always about both sides at once.
///
/// A suite that looked only at English would pass a Russian notification that had lost its
/// command, named no service, or come out empty — which is the whole class of mistake a second
/// language brings with it. So the checks here ask the same question of both sides and fail if
/// either answers wrong, and a check that is genuinely about one language names that side
/// itself.
extension Phrase {
    /// Both sides, in the order a phrase is written in.
    var sides: [String] { [english, russian] }

    /// Whether something is true of both sides. The check is written once and asked twice.
    func holds(_ check: (String) -> Bool) -> Bool { sides.allSatisfy(check) }

    /// Whether each side carries its own side of another phrase.
    func carries(_ other: Phrase) -> Bool {
        english.contains(other.english) && russian.contains(other.russian)
    }

    /// Both sides at once, for a failure message that has to show what actually came out.
    var shown: String { "\(english) │ \(russian)" }
}
