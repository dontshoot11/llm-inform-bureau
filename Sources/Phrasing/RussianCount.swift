import Foundation

/// A noun after a number, in the form Russian puts it in.
///
/// English needs nothing of the kind: one day, two days, five days is a single rule and a
/// letter on the end. Russian picks between three forms by the last digits of the number, so a
/// sentence built by standing a number in front of one fixed word is wrong two times out of
/// three, and wrong in the way a reader reads as a machine talking.
///
/// Only the counting this app actually does is here — days, hours, minutes. A general
/// pluraliser would be a rule engine with one caller.
enum RussianCount {
    /// The number and the noun together, which is the only way any caller wants them.
    ///
    /// The three forms in the order Russian asks for them: what follows one, what follows two,
    /// what follows five. The teens are the exception that makes the rule worth a function —
    /// eleven through fourteen take the last of the three however they end.
    static func of(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let lastTwo = abs(count) % 100
        let last = abs(count) % 10
        let noun: String
        if lastTwo >= 11 && lastTwo <= 14 {
            noun = many
        } else if last == 1 {
            noun = one
        } else if last >= 2 && last <= 4 {
            noun = few
        } else {
            noun = many
        }
        return "\(count) \(noun)"
    }
}
