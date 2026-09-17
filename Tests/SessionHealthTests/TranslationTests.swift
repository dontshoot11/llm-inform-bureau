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
    let phrasing = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Tests/SessionHealthTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // the package root
        .appendingPathComponent("Sources/Phrasing", isDirectory: true)

    let files = ((try? FileManager.default.contentsOfDirectory(atPath: phrasing.path)) ?? [])
        .filter { $0.hasSuffix(".swift") }
        .sorted()

    var literals: [FoundLiteral] = []
    var phrases: [PhraseCall] = []
    var unreadable: [String] = []
    for file in files {
        guard let text = try? String(contentsOf: phrasing.appendingPathComponent(file), encoding: .utf8) else {
            unreadable.append(file)
            continue
        }
        let read = readSwift(text, in: file)
        literals += read.literals
        phrases += read.phrases
    }

    suite.test("the phrasing is where this test thinks it is, and all of it was read") {
        suite.expect(files.count > 5, "found \(files.count) Swift files under \(phrasing.path)")
        suite.expect(unreadable.isEmpty, "could not read \(unreadable)")
        suite.expect(literals.count > 100, "only \(literals.count) strings found — the reader is not reading")
        suite.expect(phrases.count > 50, "only \(phrases.count) phrases found — the reader is not reading")
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
        for literal in literals {
            let claims = QualityClaims.found(in: literal.text)
            suite.expect(
                claims.isEmpty,
                "\(literal.file):\(literal.line) — \(claims) in: \"\(literal.text)\""
            )
        }
    }
}

/// One string literal as it stands in the source: what it says, where it is, and the call it is
/// an argument of.
private struct FoundLiteral {
    let file: String
    let line: Int
    let text: String
    /// The name in front of the innermost open bracket around it, or empty at the top level.
    let enclosing: String
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
    /// The calls currently open, innermost last: what each bracket was called and where it began.
    var open: [(name: String, from: Int, line: Int)] = []
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
                FoundLiteral(file: file, line: startedAt, text: text, enclosing: open.last?.name ?? "")
            )
            word = ""
            continue
        }

        if character == "(" {
            open.append((name: word, from: index, line: line))
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
