import Foundation
import Phrasing
import SessionHealthCore

/// Which language the app opens in, and what a person's own answer to that is worth.
///
/// Two things are held here. One is the record: a language picked in the settings window has to
/// survive a restart and a new copy dragged over the old one, or the app is overruling somebody
/// every time they update it. The other is the order the two answers come in — a choice
/// outranks the Mac, and the absence of a choice is not the same as a choice of English, which
/// is the difference between an app that follows the system and one that only looks like it.
func runLanguageChoiceTests(_ suite: TestSuite, config: ThresholdConfig) {
    // MARK: The record

    withTemporaryDirectory(suite, named: "language-choice") { directory in
        let url = LanguageChoice.url(in: directory)

        suite.test("an app nobody has answered leaves nothing on the disk") {
            suite.expectEqual(LanguageChoice.chosen(at: url), nil, "choice with nothing written")
            suite.expect(
                !FileManager.default.fileExists(atPath: url.path),
                "somebody who never opened the window must leave no file behind"
            )
        }

        // A restart is nothing but this: the answer comes off the disk rather than out of a
        // process that has since ended.
        suite.test("a language comes back the way it was picked") {
            suite.expect(LanguageChoice.choose(.russian, at: url), "written")
            suite.expectEqual(LanguageChoice.chosen(at: url), .russian, "read back")
            suite.expect(LanguageChoice.choose(.english, at: url), "written again")
            suite.expectEqual(LanguageChoice.chosen(at: url), .english, "read back a second time")
        }

        // The difference the whole design rests on: English on the disk is an answer, and it
        // has to outlive somebody switching their Mac to Russian.
        suite.test("choosing English is a choice and not the absence of one") {
            suite.expect(LanguageChoice.choose(.english, at: url), "written")
            suite.expectEqual(LanguageChoice.chosen(at: url), .english, "read back")
            suite.expectEqual(
                LanguageInUse.atLaunch(chosen: LanguageChoice.chosen(at: url), system: ["ru-RU"]),
                .english,
                "a Russian Mac must not overrule somebody who asked for English"
            )
        }

        suite.test("going back to following the Mac takes the choice off the disk") {
            suite.expect(LanguageChoice.choose(.russian, at: url), "chosen")
            suite.expect(LanguageChoice.choose(nil, at: url), "put back")
            suite.expectEqual(LanguageChoice.chosen(at: url), nil, "no choice left")
            suite.expect(
                !FileManager.default.fileExists(atPath: url.path),
                "nothing must be left for a later release to read"
            )
        }

        suite.test("picking the same language twice is not an error, and neither is undoing twice") {
            suite.expect(LanguageChoice.choose(.russian, at: url), "chosen")
            suite.expect(LanguageChoice.choose(.russian, at: url), "chosen again")
            suite.expectEqual(LanguageChoice.chosen(at: url), .russian, "still Russian")
            suite.expect(LanguageChoice.choose(nil, at: url), "put back")
            suite.expect(LanguageChoice.choose(nil, at: url), "put back again")
            suite.expectEqual(LanguageChoice.chosen(at: url), nil, "still following the Mac")
        }

        // Nothing here throws, and a file that cannot be understood is not half an answer: the
        // app goes to the Mac, exactly as it does where the file was never written.
        suite.test("a file that says nothing the app understands is nobody having chosen") {
            try? Data("\n".utf8).write(to: url, options: .atomic)
            suite.expectEqual(LanguageChoice.chosen(at: url), nil, "an empty first line")
            try? Data().write(to: url, options: .atomic)
            suite.expectEqual(LanguageChoice.chosen(at: url), nil, "an empty file")
            try? Data("edited by hand\n".utf8).write(to: url, options: .atomic)
            suite.expectEqual(LanguageChoice.chosen(at: url), nil, "a sentence where a code should be")
            // The shape a release that spoke three languages would leave behind.
            try? Data("de\n".utf8).write(to: url, options: .atomic)
            suite.expectEqual(LanguageChoice.chosen(at: url), nil, "a language this app does not speak")
            suite.expect(LanguageChoice.choose(nil, at: url), "cleaned up")
        }

        suite.test("the code is the first line and the rest is a note to whoever opens it") {
            let moment = Date(timeIntervalSince1970: 1_789_000_000)
            suite.expect(LanguageChoice.choose(.russian, at: url, on: moment), "written")
            let file = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            suite.expectEqual(
                file.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init),
                "ru",
                "the first line is the answer"
            )
            suite.expect(
                file.contains(ISO8601DateFormatter().string(from: moment)),
                "the file must say when the language was picked: \(file)"
            )
            suite.expect(
                file.lowercased().contains("delete this file"),
                "somebody who finds this file must be told how to undo it: \(file)"
            )
            suite.expectEqual(LanguageChoice.chosen(at: url), .russian, "still read as the choice")
            suite.expect(LanguageChoice.choose(nil, at: url), "cleaned up")
        }

        suite.test("whitespace around the code is a person's editor, not a different answer") {
            try? Data("  ru  \nwhatever else\n".utf8).write(to: url, options: .atomic)
            suite.expectEqual(LanguageChoice.chosen(at: url), .russian, "read back")
            suite.expect(LanguageChoice.choose(nil, at: url), "cleaned up")
        }

        suite.test("a directory that is not there yet is made rather than failed over") {
            let nested = LanguageChoice.url(in: directory.appendingPathComponent("made-on-the-way"))
            suite.expect(LanguageChoice.choose(.russian, at: nested), "written")
            suite.expectEqual(LanguageChoice.chosen(at: nested), .russian, "read back")
        }
    }

    // What carries the choice across an update: a copy dragged over the old one replaces the
    // bundle and never touches Application Support. The same argument as the marks and the
    // silence, and the same directory.
    suite.test("the language is kept beside the marks that were moved and the silence that was asked for") {
        let home = URL(fileURLWithPath: "/Users/nobody")
        let directory = SupportDirectory.url(home: home)
        suite.expectEqual(
            LanguageChoice.url(in: directory).deletingLastPathComponent().path,
            NotificationChoice.url(in: directory).deletingLastPathComponent().path,
            "the choices must live together"
        )
        suite.expect(
            !LanguageChoice.url(in: directory).path.contains(".app/"),
            "a choice inside the bundle would not survive a new copy dragged over it"
        )
    }

    // MARK: Which language the app opens in

    suite.test("nobody having chosen means following the Mac") {
        suite.expectEqual(LanguageInUse.atLaunch(chosen: nil, system: ["ru-RU", "en-GB"]), .russian, "a Russian Mac")
        suite.expectEqual(LanguageInUse.atLaunch(chosen: nil, system: ["en-GB"]), .english, "an English Mac")
    }

    suite.test("a choice outranks the Mac whichever way round they are") {
        suite.expectEqual(LanguageInUse.atLaunch(chosen: .russian, system: ["en-US"]), .russian, "Russian on an English Mac")
        suite.expectEqual(LanguageInUse.atLaunch(chosen: .english, system: ["ru-RU"]), .english, "English on a Russian Mac")
    }

    // The list is tags rather than languages, and it is in the person's own order of
    // preference: the first entry this app can speak is the one they would rather read.
    suite.test("the Mac's list is read by its first entry this app speaks") {
        suite.expectEqual(LanguageInUse.ofSystem(["ru"]), .russian, "a bare code")
        suite.expectEqual(LanguageInUse.ofSystem(["ru-RU"]), .russian, "a code with a region")
        suite.expectEqual(LanguageInUse.ofSystem(["RU-ru"]), .russian, "a code in capitals")
        suite.expectEqual(LanguageInUse.ofSystem(["fr-FR", "ru-RU", "en-US"]), .russian, "past a language it does not speak")
        suite.expectEqual(LanguageInUse.ofSystem(["fr-FR", "de-DE"]), .english, "a Mac in neither language")
        suite.expectEqual(LanguageInUse.ofSystem([]), .english, "a Mac that answered nothing")
    }

    // MARK: A phrase has two sides

    suite.test("a phrase says one side per language and nothing in between") {
        let phrase = Phrase("Settings", "Настройки")
        suite.expectEqual(phrase[.english], "Settings", "the English side")
        suite.expectEqual(phrase[.russian], "Настройки", "the Russian side")
        suite.expectEqual(
            phrase.mapped { "\($0)…" },
            Phrase("Settings…", "Настройки…"),
            "building on a phrase must build on both sides"
        )
    }

    // The point of the type: the language of the window is chosen where it is drawn, so one
    // phrase can be read two ways in one run without anything being reloaded.
    suite.test("the same phrase answers to both languages in one run") {
        suite.expectEqual(Briefing.windowTitle[.english], "Settings", "English")
        suite.expect(Briefing.windowTitle[.russian] != Briefing.windowTitle[.english], "translated")
        suite.expect(!Briefing.windowTitle[.russian].isEmpty, "the Russian side is written")
    }
}
