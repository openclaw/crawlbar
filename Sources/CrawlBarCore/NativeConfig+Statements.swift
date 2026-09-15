import Foundation

extension CrawlNativeConfigStore {
    // Only statement starts can declare a table or a scalar key. Multiline values
    // may contain identical text and must remain opaque to configuration edits.
    static func statementIndices(in lines: [String]) -> [Int] {
        var statements: [Int] = []
        var multilineQuote: Character?
        var nesting = 0
        for (lineIndex, line) in lines.enumerated() {
            if multilineQuote == nil, nesting == 0 {
                statements.append(lineIndex)
            }
            let characters = Array(line)
            var index = 0
            var quote: Character?
            while index < characters.count {
                let character = characters[index]
                let isTriple = index + 2 < characters.count
                    && characters[index + 1] == character && characters[index + 2] == character
                if let delimiter = multilineQuote {
                    if delimiter == "\"", character == "\\" {
                        index += 2
                    } else if character == delimiter, isTriple {
                        multilineQuote = nil
                        index += 3
                        // TOML permits one or two content quotes immediately before the closing triple.
                        while index < characters.count, characters[index] == delimiter {
                            index += 1
                        }
                    } else {
                        index += 1
                    }
                    continue
                }
                if let delimiter = quote {
                    if delimiter == "\"", character == "\\" {
                        index += 2
                        continue
                    }
                    if character == delimiter { quote = nil }
                    index += 1
                    continue
                }
                if character == "#" { break }
                if character == "\"" || character == "'" {
                    if isTriple {
                        multilineQuote = character
                        index += 3
                    } else {
                        quote = character
                        index += 1
                    }
                    continue
                }
                if character == "[" || character == "{" {
                    nesting += 1
                } else if character == "]" || character == "}" {
                    nesting = max(0, nesting - 1)
                }
                index += 1
            }
        }
        return statements
    }

    static func keyPathComponents(_ key: String) -> [String] {
        var components: [String] = []
        var part = ""
        var quote: Character?
        var escaped = false
        for character in key {
            if let delimiter = quote {
                part.append(character)
                if escaped {
                    escaped = false
                } else if delimiter == "\"", character == "\\" {
                    escaped = true
                } else if character == delimiter {
                    quote = nil
                }
            } else if character == "." {
                components.append(part.trimmingCharacters(in: .whitespaces))
                part = ""
            } else {
                if character == "\"" || character == "'" { quote = character }
                part.append(character)
            }
        }
        components.append(part.trimmingCharacters(in: .whitespaces))
        return components.map { value in
            if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                return String(value.dropFirst().dropLast())
            }
            return Self.decodeBasicKey(value)
        }
    }

    private static func decodeBasicKey(_ value: String) -> String {
        guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else { return value }
        let characters = Array(value.dropFirst().dropLast())
        let escapes: [Character: String] = [
            "b": "\u{8}", "t": "\t", "n": "\n", "f": "\u{c}", "r": "\r", "\"": "\"", "\\": "\\",
        ]
        var decoded = ""
        var index = 0
        while index < characters.count {
            guard characters[index] == "\\" else {
                decoded.append(characters[index])
                index += 1
                continue
            }
            index += 1
            guard index < characters.count else { return value }
            let escape = characters[index]
            index += 1
            if let replacement = escapes[escape] {
                decoded += replacement
            } else if escape == "u" || escape == "U" {
                let length = escape == "u" ? 4 : 8
                guard index + length <= characters.count,
                      let code = UInt32(String(characters[index..<(index + length)]), radix: 16),
                      let scalar = UnicodeScalar(code)
                else { return value }
                decoded.unicodeScalars.append(scalar)
                index += length
            } else {
                return value
            }
        }
        return decoded
    }
}
