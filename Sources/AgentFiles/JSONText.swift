import Foundation

/// Editing one key of a JSON file without rewriting the rest of it.
///
/// This exists because `settings.json` belongs to the user. Parsing it into a dictionary and
/// serialising it back changes three things nobody asked to change — the order of the keys,
/// every slash in every path, the space before every colon — and turns a one-key edit into a
/// diff across the whole file. So the file is treated as text: find where the value of a key
/// sits, put other bytes there, leave everything else exactly as it was.
///
/// Not a JSON parser and not trying to be one. It walks an object far enough to say where each
/// member starts and ends, which is all that replacing one of them needs, and it is only ever
/// run on text `JSONSerialization` has already accepted — `ClaudeSettings` refuses anything
/// else before this is reached. Keys are compared as raw bytes, which is exact for the plain
/// names this looks for (`statusLine`, `command`, `type`) and would not be for a key written
/// with escapes; such a key simply is not found, and the member is added rather than replaced.
///
/// Indices are into UTF-8 bytes rather than into a `String`: every character JSON gives
/// structure to is ASCII, so a byte scan cannot land in the middle of anything, and the bytes
/// of what is not being touched are copied across untouched.
enum JSONText {
    // MARK: What this is for

    /// The file with `statusLine.command` set to `command`, or `nil` when there is nothing to
    /// edit. Anything else inside `statusLine` — `padding`, `refreshInterval` — is the user's
    /// and is kept.
    static func settingStatusLine(to command: String, in bytes: [UInt8]) -> [UInt8]? {
        guard let start = objectStart(of: bytes) else { return nil }
        guard let slot = members(inObjectAt: start, of: bytes).first(where: { $0.key == "statusLine" }) else {
            return inserting(
                key: "statusLine",
                value: object(["type": string("command"), "command": string(command)], like: bytes, at: start),
                intoObjectAt: start,
                of: bytes
            )
        }
        // A `statusLine` that is not an object is not something this app can add a key to. It
        // is also not a shape Claude Code reads, so replacing it whole is the only move that
        // leaves the file meaning anything.
        guard bytes[slot.value.lowerBound] == Byte.openBrace else {
            return replacing(
                slot.value,
                with: object(["type": string("command"), "command": string(command)], like: bytes, at: start),
                in: bytes
            )
        }
        var result = set("command", to: string(command), inObjectAt: slot.value.lowerBound, of: bytes)
        // Set one at a time and rescanned in between: the first edit moves every index after
        // it, and two edits planned against the same scan would land the second in the wrong
        // place.
        guard let start = objectStart(of: result),
              let slot = members(inObjectAt: start, of: result).first(where: { $0.key == "statusLine" })
        else { return result }
        result = set("type", to: string("command"), inObjectAt: slot.value.lowerBound, of: result)
        return result
    }

    /// The file with the whole `statusLine` key taken out, or `nil` when it was not there.
    static func removingStatusLine(in bytes: [UInt8]) -> [UInt8]? {
        guard let start = objectStart(of: bytes),
              let slot = members(inObjectAt: start, of: bytes).first(where: { $0.key == "statusLine" })
        else { return nil }
        return removing(slot, inObjectAt: start, of: bytes)
    }

    // MARK: One member of an object

    /// Where one key and its value sit: the key's opening quote through the end of the value,
    /// and the value on its own.
    struct Member {
        let key: String
        let whole: Range<Int>
        let value: Range<Int>
    }

    /// Every member of the object whose `{` is at `start`, in the order the file has them.
    ///
    /// Stops at the first thing it does not understand rather than guessing. The caller has
    /// already had the text accepted by a real parser, so that can only be a member shape this
    /// scan has no business editing — and returning what was read so far means the key being
    /// looked for is either found before that point or treated as absent.
    static func members(inObjectAt start: Int, of bytes: [UInt8]) -> [Member] {
        var found: [Member] = []
        var index = start + 1
        while index < bytes.count {
            index = skippingSpace(from: index, of: bytes)
            guard index < bytes.count, bytes[index] != Byte.closeBrace else { return found }
            guard bytes[index] == Byte.quote, let keyEnd = endOfString(from: index, of: bytes) else {
                return found
            }
            let key = String(decoding: bytes[(index + 1)..<(keyEnd - 1)], as: UTF8.self)
            let afterKey = skippingSpace(from: keyEnd, of: bytes)
            guard afterKey < bytes.count, bytes[afterKey] == Byte.colon else { return found }
            let valueStart = skippingSpace(from: afterKey + 1, of: bytes)
            guard let valueEnd = endOfValue(from: valueStart, of: bytes) else { return found }
            found.append(Member(key: key, whole: index..<valueEnd, value: valueStart..<valueEnd))
            index = skippingSpace(from: valueEnd, of: bytes)
            if index < bytes.count, bytes[index] == Byte.comma { index += 1 }
        }
        return found
    }

    /// Sets one key of the object at `start` to `value`, adding it when it is not there.
    private static func set(
        _ key: String,
        to value: String,
        inObjectAt start: Int,
        of bytes: [UInt8]
    ) -> [UInt8] {
        if let member = members(inObjectAt: start, of: bytes).first(where: { $0.key == key }) {
            return replacing(member.value, with: value, in: bytes)
        }
        return inserting(key: key, value: value, intoObjectAt: start, of: bytes) ?? bytes
    }

    /// Adds a member at the front of an object, laid out the way its neighbours are.
    ///
    /// At the front rather than the end because that is where the whitespace to copy is: the
    /// gap between `{` and the first member says how this file indents, and reusing it is what
    /// keeps the edit from looking like an edit.
    private static func inserting(
        key: String,
        value: String,
        intoObjectAt start: Int,
        of bytes: [UInt8]
    ) -> [UInt8]? {
        guard start < bytes.count, bytes[start] == Byte.openBrace else { return nil }
        let afterBrace = start + 1
        let firstMember = skippingSpace(from: afterBrace, of: bytes)
        let gap = String(decoding: bytes[afterBrace..<firstMember], as: UTF8.self)
        let isEmpty = firstMember >= bytes.count || bytes[firstMember] == Byte.closeBrace

        var insert = gap.isEmpty ? " " : gap
        insert += "\(string(key)): \(value)"
        if !isEmpty { insert += "," }

        var result = bytes
        result.insert(contentsOf: Array(insert.utf8), at: afterBrace)
        return result
    }

    /// Takes a member out along with the comma that joined it to its neighbours, leaving no
    /// blank line where it was and no trailing comma behind it.
    private static func removing(_ member: Member, inObjectAt start: Int, of bytes: [UInt8]) -> [UInt8] {
        var cutStart = startOfSpace(before: member.whole.lowerBound, of: bytes)
        var cutEnd = member.whole.upperBound

        let next = skippingSpace(from: cutEnd, of: bytes)
        if next < bytes.count, bytes[next] == Byte.comma {
            cutEnd = next + 1
        } else if cutStart - 1 > start, bytes[cutStart - 1] == Byte.comma {
            // The last member of the object: the comma in front of it has nothing left to
            // join, and a JSON object with a trailing comma is not JSON.
            cutStart = startOfSpace(before: cutStart - 1, of: bytes)
        }

        var result = bytes
        result.removeSubrange(cutStart..<cutEnd)
        return result
    }

    private static func replacing(_ range: Range<Int>, with text: String, in bytes: [UInt8]) -> [UInt8] {
        var result = bytes
        result.replaceSubrange(range, with: Array(text.utf8))
        return result
    }

    // MARK: Writing values out

    /// A string as JSON writes it — with the slashes left alone. `JSONSerialization` escapes
    /// them, and a path full of `\/` in a file somebody reads by hand is a change they did not
    /// ask for.
    static func string(_ value: String) -> String {
        var out = "\""
        for character in value.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if character.value < 0x20 {
                    out += String(format: "\\u%04x", character.value)
                } else {
                    out.unicodeScalars.append(character)
                }
            }
        }
        return out + "\""
    }

    /// An object literal indented the way the file indents its own members — one step deeper
    /// than the top level, since that is where this one is going. A file written on one line
    /// gets it on one line.
    private static func object(_ members: KeyValuePairs<String, String>, like bytes: [UInt8], at start: Int) -> String {
        let pairs = members.map { "\(string($0.key)): \($0.value)" }
        guard let indent = indentation(ofObjectAt: start, of: bytes) else {
            return "{\(pairs.joined(separator: ", "))}"
        }
        // `indent` carries its own line break, since that is how it was read out of the file.
        let inner = indent + indent.replacingOccurrences(of: "\n", with: "")
        return "{\(inner)" + pairs.joined(separator: ",\(inner)") + "\(indent)}"
    }

    /// How this file sets out a member of the object at `start`: the run of whitespace before
    /// the first one, when it holds a line break. `nil` for an object written on one line, and
    /// for an empty one — neither has anything to copy.
    private static func indentation(ofObjectAt start: Int, of bytes: [UInt8]) -> String? {
        let afterBrace = start + 1
        let firstMember = skippingSpace(from: afterBrace, of: bytes)
        guard firstMember < bytes.count, bytes[firstMember] != Byte.closeBrace else { return nil }
        let gap = String(decoding: bytes[afterBrace..<firstMember], as: UTF8.self)
        guard let lastBreak = gap.lastIndex(of: "\n") else { return nil }
        return "\n" + gap[gap.index(after: lastBreak)...]
    }

    // MARK: Walking the text

    /// The `{` the whole file is.
    static func objectStart(of bytes: [UInt8]) -> Int? {
        let index = skippingSpace(from: 0, of: bytes)
        guard index < bytes.count, bytes[index] == Byte.openBrace else { return nil }
        return index
    }

    /// One past the closing quote of the string starting at `index`.
    private static func endOfString(from index: Int, of bytes: [UInt8]) -> Int? {
        var current = index + 1
        while current < bytes.count {
            if bytes[current] == Byte.backslash {
                current += 2
                continue
            }
            if bytes[current] == Byte.quote { return current + 1 }
            current += 1
        }
        return nil
    }

    /// One past the end of the value starting at `index`, whatever kind of value it is.
    private static func endOfValue(from index: Int, of bytes: [UInt8]) -> Int? {
        guard index < bytes.count else { return nil }
        switch bytes[index] {
        case Byte.quote:
            return endOfString(from: index, of: bytes)
        case Byte.openBrace, Byte.openBracket:
            var depth = 0
            var current = index
            while current < bytes.count {
                switch bytes[current] {
                case Byte.quote:
                    guard let end = endOfString(from: current, of: bytes) else { return nil }
                    current = end
                    continue
                case Byte.openBrace, Byte.openBracket:
                    depth += 1
                case Byte.closeBrace, Byte.closeBracket:
                    depth -= 1
                    if depth == 0 { return current + 1 }
                default:
                    break
                }
                current += 1
            }
            return nil
        default:
            // A number, `true`, `false`, `null`: everything up to whatever ends it.
            var current = index
            while current < bytes.count, !isSpace(bytes[current]), !Byte.closers.contains(bytes[current]) {
                current += 1
            }
            return current > index ? current : nil
        }
    }

    private static func skippingSpace(from index: Int, of bytes: [UInt8]) -> Int {
        var current = index
        while current < bytes.count, isSpace(bytes[current]) { current += 1 }
        return current
    }

    /// The first byte of the run of whitespace that ends just before `index`.
    private static func startOfSpace(before index: Int, of bytes: [UInt8]) -> Int {
        var current = index
        while current > 0, isSpace(bytes[current - 1]) { current -= 1 }
        return current
    }

    private static func isSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }

    private enum Byte {
        static let quote = UInt8(ascii: "\"")
        static let backslash = UInt8(ascii: "\\")
        static let colon = UInt8(ascii: ":")
        static let comma = UInt8(ascii: ",")
        static let openBrace = UInt8(ascii: "{")
        static let closeBrace = UInt8(ascii: "}")
        static let openBracket = UInt8(ascii: "[")
        static let closeBracket = UInt8(ascii: "]")
        static let closers: Set<UInt8> = [comma, closeBrace, closeBracket]
    }
}
