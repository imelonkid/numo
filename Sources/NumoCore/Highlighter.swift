import Foundation

public enum HighlightKind: Sendable, Equatable {
    case number, op, unit, keyword, function, constant, variable, comment, label
}

public struct Highlight: Sendable, Equatable {
    /// UTF-16 offsets within the line.
    public let range: Range<Int>
    public let kind: HighlightKind
}

public enum Highlighter {
    public static func highlights(for line: String, registry: CurrencyRegistry = .standard) -> [Highlight] {
        let parts = LineSplitter.split(line)
        var out: [Highlight] = []
        if let l = parts.label { out.append(Highlight(range: l, kind: .label)) }

        for t in Lexer.tokenize(parts.body, registry: registry) {
            let r = (t.range.lowerBound + parts.bodyOffset)..<(t.range.upperBound + parts.bodyOffset)
            let kind: HighlightKind
            switch t.kind {
            case .number: kind = .number
            case .currency: kind = .unit
            case .symbol: kind = .op
            case .identifier(let w):
                let lower = w.lowercased()
                if registry.code(forAlias: w) != nil || Keywords.radixTargets[lower] != nil {
                    kind = .unit
                } else if Keywords.functions.contains(lower) {
                    kind = .function
                } else if Keywords.constants.contains(lower) {
                    kind = .constant
                } else if Keywords.isReserved(w) {
                    kind = .keyword
                } else {
                    kind = .variable
                }
            }
            out.append(Highlight(range: r, kind: kind))
        }

        if let c = parts.comment { out.append(Highlight(range: c, kind: .comment)) }
        return out
    }
}
