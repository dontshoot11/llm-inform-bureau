import Foundation
import SwiftUI
import Phrasing
import SessionHealthCore

/// The language the app is speaking right now, and the way to change it while it runs.
///
/// One object, held by the app and handed to both of its roots — the panel and the settings
/// window — so that the two cannot be in different languages. Everything that draws a word
/// takes it from here, and a change to it redraws both, which is the whole of "without
/// restarting": a `Phrase` is not resolved until something draws it.
///
/// It lives in the app rather than in `Phrasing` on purpose. `Phrasing` is imported by the
/// tests, and a current language kept there would be one global that every test could leave
/// changed for the next one. The target that speaks holds the words; the app holds which side
/// of them is showing.
@MainActor
final class InterfaceLanguage: ObservableObject {
    /// The one in the running app. Two of these would be two languages.
    static let shared = InterfaceLanguage()

    @Published private(set) var current: Language

    /// Whether the language on screen is somebody's choice rather than the Mac's. The picker
    /// and the line under it both read this, so the control and its explanation cannot come to
    /// describe different states.
    @Published private(set) var isChosen: Bool

    /// The Mac's own language list. Taken once and kept, because that is what the fallback is
    /// measured against when somebody puts the app back to following it — and because a test
    /// needs to name it.
    private let system: [String]

    init(
        chosen: Language? = LanguageChoice.chosen(),
        system: [String] = Locale.preferredLanguages
    ) {
        self.system = system
        self.current = LanguageInUse.atLaunch(chosen: chosen, system: system)
        self.isChosen = chosen != nil
    }

    /// One phrase, as it is being said. The call every view makes.
    func say(_ phrase: Phrase) -> String { phrase[current] }

    /// Somebody picked a language. Written down first, so that the app on screen and the app
    /// after a restart agree even if the disk refuses — a failed write leaves the choice
    /// showing and the file absent, which the next appearance of the row will correct.
    func choose(_ language: Language) {
        LanguageChoice.choose(language)
        current = language
        isChosen = true
    }

    /// Back to following the Mac: the file goes away, and the language becomes whatever the
    /// system asks for — which may well be the one already on screen.
    func followTheMac() {
        LanguageChoice.choose(nil)
        current = LanguageInUse.ofSystem(system)
        isChosen = false
    }

    /// Reads the choice off the disk again.
    ///
    /// For the same reason the other choices kept in that directory are asked for every time
    /// rather than remembered: the file is something a person can delete while the app runs, and
    /// a picker insisting on a choice that is no longer on disk is a control lying about
    /// itself.
    func readAgain() {
        let chosen = LanguageChoice.chosen()
        current = LanguageInUse.atLaunch(chosen: chosen, system: system)
        isChosen = chosen != nil
    }
}

/// The row that picks the language, at the top of the settings window.
///
/// First line of the window because it governs every word below it: somebody who opened this
/// window to change the language should not have to read a screenful of the wrong one to find
/// the control. Below it stands the line that says which state the picker is in — following the
/// Mac, or holding a choice — read off the same object the picker sets, so the two cannot
/// disagree.
///
/// Segmented rather than a menu: there are two languages, both fit, and a menu would hide half
/// the answer behind a click. Each is named in itself, so a reader looking for Russian in an
/// English app finds "Русский" rather than a word they may not read.
struct LanguagePicker: View {
    @EnvironmentObject private var interface: InterfaceLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(interface.say(Briefing.languageTitle))
                    .font(WindowType.item)
                Picker("", selection: Binding(
                    get: { interface.current },
                    set: { interface.choose($0) }
                )) {
                    ForEach(Language.allCases, id: \.self) { language in
                        Text(Briefing.languageName(language)).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                // Only once there is a choice to undo, the same as the button under a mark
                // somebody moved: a control that does nothing is one more thing to read past.
                if interface.isChosen {
                    Button(interface.say(Briefing.languageFollowMac)) { interface.followTheMac() }
                        .buttonStyle(.link)
                        .font(WindowType.detail)
                }
            }
            Text(interface.say(interface.isChosen ? Briefing.languageChosen : Briefing.languageFollowsMac))
                .font(WindowType.detail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { interface.readAgain() }
    }
}
