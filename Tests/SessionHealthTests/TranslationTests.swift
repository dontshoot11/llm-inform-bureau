import Foundation
import Phrasing

/// That the app speaks both of its languages everywhere, and that neither of them says
/// something the app has no business saying.
///
/// The compiler already carries most of this: a `Phrase` cannot be built without both sides, so
/// a sentence added with one side does not compile. What the compiler cannot see is a sentence
/// that never became a `Phrase` at all — a plain `String` sitting in the phrasing target, which
/// compiles perfectly and reaches a Russian window in English. That is what this reads the
/// source for, in the genre `OfflineTests` set: the rule is about what is *not* written, so the
/// thing to read is the text of the files.
///
/// It also catches the other half of the same mistake, the one a reader of a review misses
/// easily: a `Phrase` whose second argument is the English sentence copied across. A phrase
/// with nothing Russian anywhere in it is that, and it fails here.
func runTranslationTests(_ suite: TestSuite) {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/SessionHealthTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // the package root

    let phrasing = read("Sources/Phrasing", under: root)
    let views = read("Sources/LLMInformBureau", under: root)
    let files = read("Sources/AgentFiles", under: root)
    let everywhere = [phrasing, views, files]

    suite.test("the sources are where this test thinks they are, and all of them were read") {
        for target in everywhere {
            suite.expect(
                target.files > 5,
                "found \(target.files) Swift files under \(target.path)"
            )
            suite.expect(target.unreadable.isEmpty, "could not read \(target.unreadable)")
        }
        suite.expect(
            phrasing.literals.count > 100,
            "only \(phrasing.literals.count) strings found — the reader is not reading"
        )
        suite.expect(
            phrasing.phrases.count > 50,
            "only \(phrasing.phrases.count) phrases found — the reader is not reading"
        )
        suite.expect(
            views.literals.count > 20,
            "only \(views.literals.count) strings found in the views — the reader is not reading"
        )
    }

    let literals = phrasing.literals
    let phrases = everywhere.flatMap(\.phrases)

    // The rule for the target the views draw from. A view has other strings to hold — an SF
    // Symbol, an AppleScript, a coordinate space — so the question here is not whether a
    // string is a sentence but whether it is going on screen: a literal handed to one of the
    // calls that draw words is a word that will arrive in whatever language it was typed in,
    // whatever the reader picked.
    //
    // Empty ones are allowed, and are not an oversight: `Picker("")`, `TextField("")` and
    // `Stepper("")` are how SwiftUI is told a control carries no label of its own.
    // The rule that catches what the one above cannot: a word put together in a view, kept in
    // a variable and drawn a screenful later. A space with a letter beside it is a word, and
    // words live in `Phrasing` — the app target has none of its own, so the whole of it is the
    // rule, with no list of allowed sentences to keep up to date.
    //
    // What is left is a token: an SF Symbol, a path, a key equivalent, a coordinate space, the
    // word an AppleScript answers with. Punctuation between two phrases has no letters in it
    // and is not a word either.
    suite.test("no word is written in a view") {
        for literal in views.literals {
            let hasWord = literal.text.contains(" ") && literal.text.contains(where: \.isLetter)
            suite.expect(
                !hasWord,
                "\(literal.file):\(literal.line) — a word written in a view: \"\(literal.text)\""
            )
        }
    }

    suite.test("nothing in a view is drawn from a string written in the view") {
        for literal in views.literals {
            let drawn = (screenCalls.contains(literal.enclosing) && literal.label.isEmpty)
                || screenLabels.contains(literal.label)
            guard drawn else { continue }
            suite.expect(
                literal.text.isEmpty,
                "\(literal.file):\(literal.line) — \(literal.enclosing) draws a string written here: \"\(literal.text)\""
            )
        }
    }

    // The rule the compiler cannot state. A sentence in this target is something the app says,
    // and everything the app says has two sides; a bare string that is more than one word is a
    // line that will arrive in English whatever the reader picked.
    //
    // More than one word is the test for a sentence, because the things that legitimately stay
    // as they are — a slash command, a percentage, a locale, a file name — are one token each.
    // Anything longer that genuinely does not translate says so in as many words, by being
    // `Phrase.name`.
    suite.test("every line the phrasing can say is one side of a phrase") {
        for literal in literals where isProse(literal.text) {
            suite.expect(
                literal.enclosing == "Phrase" || literal.enclosing == "Phrase.name",
                "\(literal.file):\(literal.line) — a sentence with no second side, in \(literal.enclosing.isEmpty ? "no call at all" : literal.enclosing): \"\(literal.text)\""
            )
        }
    }

    // The other half: the second side was written in the second language rather than the
    // English copied across. Asked only where that side spells its words out — a side computed
    // from something else has no words here to read, and whatever it is made of was asked this
    // question where it was written.
    suite.test("every phrase writes its second side in the second language") {
        for phrase in phrases {
            let russian = phrase.russianSide(in: phrase.file)
            guard russian.contains(where: { $0.contains(where: \.isLetter) }) else { continue }
            suite.expect(
                russian.contains(where: hasCyrillic),
                "\(phrase.file):\(phrase.line) — the second side is not in the second language: \(phrase.text)"
            )
        }
    }

    // The half of a second language that is not vocabulary. English puts a number in front of
    // a word and adds a letter to the end of it; Russian picks between three forms by the last
    // digits, and a sentence that got it wrong reads as a machine talking — which is the one
    // thing a widget that says "5 день" cannot come back from.
    suite.test("a duration said in full agrees with the number in front of it") {
        let agreed: [(minutes: Int, russian: String, english: String)] = [
            (60, "1 час", "1h"),
            (2 * 60, "2 часа", "2h"),
            (5 * 60, "5 часов", "5h"),
            (11 * 60, "11 часов", "11h"),
            (21 * 60, "21 час", "21h"),
            (24 * 60, "1 день", "1d"),
            (2 * 24 * 60, "2 дня", "2d"),
            (7 * 24 * 60, "7 дней", "7d"),
            (11 * 24 * 60, "11 дней", "11d"),
            (30, "30 минут", "30m"),
            (21, "21 минута", "21m"),
            (22, "22 минуты", "22m")
        ]
        for length in agreed {
            let said = TimeDisplay.windowLength(length.minutes)
            suite.expectEqual(said.russian, length.russian, "\(length.minutes) minutes in Russian")
            suite.expectEqual(said.english, length.english, "\(length.minutes) minutes in English")
        }
    }

    // `AGENTS.md` draws this line for everything the widget says, and the second language is
    // where a claim like that would go unnoticed. Read off the strings themselves rather than
    // off one composed sentence, so a phrase nothing in the suite happens to build is covered
    // too.
    suite.test("no side of anything the app says grades the session") {
        // Every string of the phrasing target, because every string there is something the
        // app says — and, in the two targets that merely speak, the sides of a phrase alone:
        // a file name or an SF Symbol is not a sentence, and `SessionHealthCore` is a word
        // that appears in both.
        let said = literals + [views, files].flatMap { target in
            target.literals.filter { $0.enclosing == "Phrase" || $0.enclosing == "Phrase.name" }
        }
        for literal in said {
            let claims = QualityClaims.found(in: literal.text)
            suite.expect(
                claims.isEmpty,
                "\(literal.file):\(literal.line) — \(claims) in: \"\(literal.text)\""
            )
        }
    }
}

/// The calls whose unlabelled argument is the words themselves — SwiftUI's own.
///
/// Not the app's own helpers — a caption, an explanation, a row of an entry — because those
/// take a `Phrase` and the compiler has already asked this question of them.
private let screenCalls: Set<String> = [
    "Text", "Button", "Link", "Toggle", "Picker", "TextField", "Stepper", "Label",
    "help", "accessibilityLabel", "accessibilityValue", "accessibilityHint"
]

/// The argument labels that carry words wherever they turn up. What AppKit draws goes through
/// one of these — a menu item's title, an alert's message — and beside them stand arguments
/// that are not words at all, such as the key a menu item answers to.
private let screenLabels: Set<String> = ["title", "message", "label", "placeholder"]

/// One target of the package, as this test reads it.
private struct SourcesRead {
    let path: String
    let files: Int
    let literals: [FoundLiteral]
    let phrases: [PhraseCall]
    let unreadable: [String]
}

/// Reads every Swift file of one target.
private func read(_ target: String, under root: URL) -> SourcesRead {
    let directory = root.appendingPathComponent(target, isDirectory: true)
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        .filter { $0.hasSuffix(".swift") }
        .sorted()

    var literals: [FoundLiteral] = []
    var phrases: [PhraseCall] = []
    var unreadable: [String] = []
    for name in names {
        guard let text = try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8) else {
            unreadable.append(name)
            continue
        }
        let read = readSwift(text, in: name)
        literals += read.literals
        phrases += read.phrases
    }
    return SourcesRead(
        path: directory.path,
        files: names.count,
        literals: literals,
        phrases: phrases,
        unreadable: unreadable
    )
}

/// One string literal as it stands in the source: what it says, where it is, the call it is an
/// argument of, and which argument of it.
private struct FoundLiteral {
    let file: String
    let line: Int
    let text: String
    /// The name in front of the innermost open bracket around it, or empty at the top level.
    let enclosing: String
    /// The label of the argument it is, or empty for an argument that has none.
    let label: String
}

/// One `Phrase(...)` construction, as the arguments written between its brackets.
private struct PhraseCall {
    let file: String
    let line: Int
    let text: String

    /// Every string spelled out in the second argument — the Russian side.
    ///
    /// Empty for a side computed rather than written: a date formatted in each language, a
    /// value handed in from somewhere else. Nothing is claimed about those here, because there
    /// are no words in them to read.
    func russianSide(in file: String) -> [String] {
        let characters = Array(text)
        var depth = 0
        var inString = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if inString {
                if character == "\\" { index += 2; continue }
                if character == "\"" { inString = false }
                index += 1
                continue
            }
            if character == "\"" { inString = true }
            if character == "(" || character == "[" { depth += 1 }
            if character == ")" || character == "]" { depth -= 1 }
            if character == "," && depth == 0 {
                return readSwift(String(characters[(index + 1)...]), in: file).literals.map(\.text)
            }
            index += 1
        }
        return []
    }
}

/// Whether a string is a sentence rather than a token: a letter, a space, and another letter.
private func isProse(_ text: String) -> Bool {
    let characters = Array(text)
    guard characters.count > 2 else { return false }
    for index in 1..<(characters.count - 1) where characters[index].isWhitespace {
        if characters[index - 1].isLetter && characters[index + 1].isLetter { return true }
    }
    return false
}

private func hasCyrillic(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
}

/// Reads Swift far enough to say where every string literal stands.
///
/// Not a parser and not trying to be one. It knows the four things that would otherwise make it
/// wrong about this file: a comment is not code, a string ends at an unescaped quote, an
/// interpolation is code inside a string, and the name in front of a bracket is the call that
/// bracket belongs to. Everything else it walks past.
private func readSwift(_ source: String, in file: String) -> (literals: [FoundLiteral], phrases: [PhraseCall]) {
    let characters = Array(source)
    var literals: [FoundLiteral] = []
    var phrases: [PhraseCall] = []
    /// The calls currently open, innermost last: what each bracket was called, where it began,
    /// and the label of the argument being written in it right now.
    var open: [(name: String, from: Int, line: Int, label: String)] = []
    /// The identifier being spelled right now, which is the call's name if a bracket follows it.
    var word = ""
    var index = 0
    var line = 1

    func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "."
    }

    while index < characters.count {
        let character = characters[index]
        let next = index + 1 < characters.count ? characters[index + 1] : " "

        if character == "\n" {
            line += 1
            index += 1
            word = ""
            continue
        }

        if character == "/" && next == "/" {
            while index < characters.count && characters[index] != "\n" { index += 1 }
            word = ""
            continue
        }

        if character == "/" && next == "*" {
            var depth = 1
            index += 2
            while index < characters.count && depth > 0 {
                if characters[index] == "\n" { line += 1 }
                if characters[index] == "/" && index + 1 < characters.count && characters[index + 1] == "*" {
                    depth += 1
                    index += 2
                    continue
                }
                if characters[index] == "*" && index + 1 < characters.count && characters[index + 1] == "/" {
                    depth -= 1
                    index += 2
                    continue
                }
                index += 1
            }
            word = ""
            continue
        }

        if character == "\"" {
            let startedAt = line
            var text = ""
            index += 1
            while index < characters.count && characters[index] != "\"" {
                if characters[index] == "\n" { line += 1 }
                // An escape: the character after it is part of the string whatever it is, and
                // an interpolation is code that has to be walked past rather than read.
                if characters[index] == "\\" && index + 1 < characters.count {
                    if characters[index + 1] == "(" {
                        var depth = 0
                        index += 1
                        repeat {
                            if characters[index] == "(" { depth += 1 }
                            if characters[index] == ")" { depth -= 1 }
                            if characters[index] == "\n" { line += 1 }
                            index += 1
                        } while index < characters.count && depth > 0
                        continue
                    }
                    text.append(characters[index + 1])
                    index += 2
                    continue
                }
                text.append(characters[index])
                index += 1
            }
            index += 1
            literals.append(
                FoundLiteral(
                    file: file,
                    line: startedAt,
                    text: text,
                    enclosing: open.last?.name ?? "",
                    label: open.last?.label ?? ""
                )
            )
            word = ""
            continue
        }

        if character == "(" {
            open.append((name: word, from: index, line: line, label: ""))
            word = ""
            index += 1
            continue
        }

        // `label:` in front of an argument. The fifth thing this reader knows, and the one that
        // tells a menu item's title from the key it answers to. A colon outside a call — a
        // ternary, a `case`, a type annotation — sets a label nothing ever asks about.
        if character == ":", !open.isEmpty, !word.isEmpty {
            open[open.count - 1].label = word
            word = ""
            index += 1
            continue
        }

        // The next argument, and a label that belongs to the last one.
        if character == ",", !open.isEmpty {
            open[open.count - 1].label = ""
            word = ""
            index += 1
            continue
        }

        if character == ")" {
            if let closed = open.popLast(), closed.name == "Phrase" {
                phrases.append(
                    PhraseCall(
                        file: file,
                        line: closed.line,
                        text: String(characters[(closed.from + 1)..<index])
                    )
                )
            }
            word = ""
            index += 1
            continue
        }

        word = isWordCharacter(character) ? word + String(character) : ""
        index += 1
    }

    return (literals, phrases)
}
