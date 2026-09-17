import Foundation
import SessionHealthCore

/// Which language the app opens in.
///
/// Two answers in a fixed order: the one the person picked, and failing that the one the Mac is
/// set to. That order is the whole rule — a choice outranks the system for good, so switching
/// the Mac to another language does not overrule somebody who said which one they wanted, and a
/// person who never opened the settings window gets their own language without having to.
///
/// The system's answer is `Locale.preferredLanguages`, which is the list in System Settings ›
/// General › Language & Region rather than the language of any one app. Its entries are tags —
/// `ru`, `ru-RU`, `en-GB` — so they are read by their first component: this app speaks Russian
/// or English, and every region of either is one of the two.
///
/// Anything that is neither is English. Not because English is the fallback for the world, but
/// because it is the language this app is written and reviewed in, and the side of every phrase
/// that is certain to say what it means.
public enum LanguageInUse {
    /// The language to start in, given what is on disk and what the system says.
    ///
    /// Both arguments are taken rather than read, so that the rule can be tested without a Mac
    /// set to a particular language and without a file in Application Support.
    public static func atLaunch(
        chosen: Language? = LanguageChoice.chosen(),
        system: [String] = Locale.preferredLanguages
    ) -> Language {
        if let chosen { return chosen }
        return ofSystem(system)
    }

    /// What the Mac's own language list comes to, for an app that speaks two.
    public static func ofSystem(_ preferred: [String]) -> Language {
        for tag in preferred {
            guard let code = tag.split(separator: "-").first else { continue }
            if let language = Language(rawValue: String(code).lowercased()) { return language }
        }
        return .english
    }
}
