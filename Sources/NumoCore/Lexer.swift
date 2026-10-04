import Foundation

public enum TokenKind: Equatable, Sendable {
    case number(Decimal)
    case identifier(String)
    /// Operators and punctuation, normalized (e.g. "×" → "*", "**" → "^").
    case symbol(String)
    /// A currency symbol such as "$", already resolved to its ISO code.
    case currency(String)
}

public struct Token: Equatable, Sendable {
    public let kind: TokenKind
    /// UTF-16 offsets within the source line, so the UI can map tokens to NSRanges.
    public let range: Range<Int>
}

/// Chinese words that act as keywords. They are listed here so the lexer can split
/// unspaced CJK runs such as "100美元换成人民币" into separate tokens.
enum CJKKeywords {
    static let words: Set<String> = Keywords.conversion.union(Keywords.sum).union(Keywords.previous)
        .filter { $0.unicodeScalars.contains(where: { $0.properties.isIdeographic }) }
}

public enum Lexer {
    public static func tokenize(_ line: String, registry: CurrencyRegistry = .standard) -> [Token] {
        let scalars = line.unicodeScalars.map(normalize)
        var offsets: [Int] = []
        offsets.reserveCapacity(scalars.count + 1)
        var o = 0
        for s in scalars {
            offsets.append(o)
            o += UTF16.width(s)
        }
        offsets.append(o)

        let vocabulary = registry.cjkAliases.union(CJKKeywords.words)
        let maxWordLength = vocabulary.map { $0.unicodeScalars.count }.max() ?? 0

        var tokens: [Token] = []
        let n = scalars.count
        var i = 0

        func emit(_ kind: TokenKind, _ start: Int, _ end: Int) {
            tokens.append(Token(kind: kind, range: offsets[start]..<offsets[end]))
        }
        func at(_ j: Int) -> Unicode.Scalar? { j < n ? scalars[j] : nil }

        while i < n {
            let c = scalars[i]

            if c.properties.isWhitespace {
                i += 1
                continue
            }

            // Numbers
            if isDigit(c) || (c == "." && at(i + 1).map(isDigit) == true) {
                let start = i
                if c == "0", let r = at(i + 1).flatMap(radixPrefix), let d = at(i + 2), isRadixDigit(d, r) {
                    i += 2
                    var digits = ""
                    while let d = at(i), isRadixDigit(d, r) || d == "_" {
                        if d != "_" { digits.unicodeScalars.append(d) }
                        i += 1
                    }
                    if let v = UInt64(digits, radix: r) {
                        emit(.number(Decimal(v)), start, i)
                    } else {
                        emit(.symbol("<invalid>"), start, i)
                    }
                    continue
                }

                var text = ""
                while let d = at(i) {
                    if isDigit(d) {
                        text.unicodeScalars.append(d)
                        i += 1
                    } else if d == ",", isThousandsGroup(scalars, i + 1) {
                        i += 1
                    } else if d == "_", at(i + 1).map(isDigit) == true {
                        i += 1
                    } else {
                        break
                    }
                }
                if at(i) == "." {
                    text += "."
                    i += 1
                    while let d = at(i), isDigit(d) {
                        text.unicodeScalars.append(d)
                        i += 1
                    }
                }
                // Exponent: only when followed by digits, so "2e" still means 2 × e.
                if let e = at(i), e == "e" || e == "E" {
                    if let d = at(i + 1), isDigit(d) {
                        text += "e"
                        i += 1
                    } else if let s = at(i + 1), s == "+" || s == "-" || s == "−", let d = at(i + 2), isDigit(d) {
                        text += s == "+" ? "e" : "e-"
                        i += 2
                    }
                    if text.hasSuffix("e") || text.hasSuffix("e-") {
                        while let d = at(i), isDigit(d) {
                            text.unicodeScalars.append(d)
                            i += 1
                        }
                    }
                }
                if text.hasPrefix(".") { text = "0" + text }
                if text.hasSuffix(".") { text.removeLast() }
                if let v = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) {
                    emit(.number(v), start, i)
                } else {
                    emit(.symbol("<invalid>"), start, i)
                }
                continue
            }

            // Currency symbols
            if let code = registry.code(forSymbol: c) {
                emit(.currency(code), i, i + 1)
                i += 1
                continue
            }

            // Single-letter constants that may be glued to other letters ("2πr").
            if c == "π" || c == "τ" {
                emit(.identifier(String(c)), i, i + 1)
                i += 1
                continue
            }

            // Identifiers (Latin or CJK)
            if c.properties.isAlphabetic || c == "_" {
                let start = i
                while let d = at(i), (d.properties.isAlphabetic || isDigit(d) || d == "_") && d != "π" && d != "τ" {
                    i += 1
                }
                let run = Array(scalars[start..<i])
                if run.contains(where: { $0.properties.isIdeographic }) {
                    splitCJK(run, base: start, vocabulary: vocabulary, maxWordLength: maxWordLength, emit: emit)
                } else {
                    emit(.identifier(String(String.UnicodeScalarView(run))), start, i)
                }
                continue
            }

            // Operators
            if let next = at(i + 1) {
                let isTimes = { (x: Unicode.Scalar) in x == "*" || x == "×" }
                let isMinus = { (x: Unicode.Scalar) in x == "-" || x == "−" || x == "–" }
                if isTimes(c) && isTimes(next) { emit(.symbol("^"), i, i + 2); i += 2; continue }
                if isMinus(c) && next == ">" { emit(.symbol("→"), i, i + 2); i += 2; continue }
            }
            emit(.symbol(normalizeOperator(c)), i, i + 1)
            i += 1
        }
        return tokens
    }

    /// Splits a run like "美元换成人民币" by greedily matching known words.
    /// Unknown stretches between known words become identifiers (e.g. variable names).
    private static func splitCJK(
        _ run: [Unicode.Scalar], base: Int, vocabulary: Set<String>, maxWordLength: Int,
        emit: (TokenKind, Int, Int) -> Void
    ) {
        var p = 0
        var pending: Int?
        func flush(_ end: Int) {
            if let s = pending {
                emit(.identifier(String(String.UnicodeScalarView(run[s..<end]))), base + s, base + end)
                pending = nil
            }
        }
        while p < run.count {
            var matched = 0
            for len in stride(from: min(maxWordLength, run.count - p), through: 1, by: -1) {
                if vocabulary.contains(String(String.UnicodeScalarView(run[p..<p + len]))) {
                    matched = len
                    break
                }
            }
            if matched > 0 {
                flush(p)
                emit(.identifier(String(String.UnicodeScalarView(run[p..<p + matched]))), base + p, base + p + matched)
                p += matched
            } else {
                if pending == nil { pending = p }
                p += 1
            }
        }
        flush(run.count)
    }

    /// Maps full-width ASCII (as typed by Chinese input methods) to ASCII. Keeps UTF-16 length.
    private static func normalize(_ s: Unicode.Scalar) -> Unicode.Scalar {
        if (0xFF01...0xFF5E).contains(s.value), let a = Unicode.Scalar(s.value - 0xFEE0) { return a }
        return s
    }

    private static func normalizeOperator(_ c: Unicode.Scalar) -> String {
        switch c {
        case "×", "·", "∙", "*": return "*"
        case "÷", "/": return "/"
        case "−", "–", "-": return "-"
        default: return String(c)
        }
    }

    private static func isDigit(_ c: Unicode.Scalar) -> Bool { c.value >= 48 && c.value <= 57 }

    private static func radixPrefix(_ c: Unicode.Scalar) -> Int? {
        switch c {
        case "x", "X": return 16
        case "b", "B": return 2
        case "o", "O": return 8
        default: return nil
        }
    }

    private static func isRadixDigit(_ c: Unicode.Scalar, _ radix: Int) -> Bool {
        guard let v = Int(String(c), radix: 36) else { return false }
        return v < radix
    }

    /// "1,000" → the comma is a thousands separator only when exactly three digits follow.
    private static func isThousandsGroup(_ s: [Unicode.Scalar], _ j: Int) -> Bool {
        guard j + 3 <= s.count, s[j..<j + 3].allSatisfy(isDigit) else { return false }
        return j + 3 == s.count || !isDigit(s[j + 3])
    }
}
