import Foundation

public struct LineResult: Sendable, Equatable {
    public var quantity: Quantity?
    public var error: String?
    /// Leading plain-text label such as "房租" in "房租 3000¥" (UTF-16 offsets in the line).
    public var label: Range<Int>?
    /// The line is a `sum` / `合计` line.
    public var isTotal = false

    public static let empty = LineResult()
}

/// The parts of a raw line: an optional "Label:" prefix, the expression body, and an optional comment.
struct LineParts {
    var body: String
    /// UTF-16 offset of `body` inside the original line.
    var bodyOffset: Int
    var label: Range<Int>?
    var comment: Range<Int>?
}

enum LineSplitter {
    static func split(_ line: String) -> LineParts {
        let u = Array(line.utf16)
        var end = u.count
        var comment: Range<Int>?

        // "# heading" or "// note" → comment
        let firstNonSpace = u.firstIndex(where: { $0 != 0x20 && $0 != 0x09 && $0 != 0x3000 }) ?? u.count
        if firstNonSpace < u.count && u[firstNonSpace] == 0x23 /* # */ {
            comment = firstNonSpace..<u.count
            end = firstNonSpace
        } else if let i = (0..<max(0, u.count - 1)).first(where: { u[$0] == 0x2F && u[$0 + 1] == 0x2F }) {
            comment = i..<u.count
            end = i
        }

        // "Rent: 3000" → label. Both ASCII and full-width colons.
        var start = 0
        var label: Range<Int>?
        if let c = (0..<end).first(where: { u[$0] == 0x3A || u[$0] == 0xFF1A }) {
            label = 0..<(c + 1)
            start = c + 1
        }

        let body = String(utf16CodeUnits: Array(u[start..<end]), count: end - start)
        return LineParts(body: body, bodyOffset: start, label: label, comment: comment)
    }
}

public enum Document {
    /// Evaluates every line top to bottom. Variables, `prev` and `sum` flow downwards.
    public static func evaluate(
        _ lines: [String], rates: ExchangeRates, registry: CurrencyRegistry = .standard
    ) -> [LineResult] {
        var context = EvaluationContext(rates: rates)
        var results: [LineResult] = []
        results.reserveCapacity(lines.count)

        for line in lines {
            let parts = LineSplitter.split(line)
            let tokens = Lexer.tokenize(parts.body, registry: registry)
            if tokens.isEmpty {
                if parts.comment == nil && parts.label == nil { context.blockResults = [] }
                results.append(.empty)
                continue
            }

            do {
                var result = try evaluateLine(tokens, context: &context, registry: registry)
                if result.label == nil, let l = parts.label { result.label = l }
                results.append(result)
            } catch {
                // "房租 3000¥": treat leading unknown words as a label and evaluate the rest.
                let labelCount = leadingLabelCount(tokens, context: context, registry: registry)
                if labelCount > 0, labelCount < tokens.count,
                   var result = try? evaluateLine(Array(tokens[labelCount...]), context: &context, registry: registry) {
                    let end = tokens[labelCount - 1].range.upperBound + parts.bodyOffset
                    result.label = 0..<end
                    results.append(result)
                } else {
                    var failed = LineResult(error: (error as? ParseError)?.message ?? error.localizedDescription)
                    failed.label = parts.label
                    results.append(failed)
                }
            }
        }
        return results
    }

    private static func evaluateLine(
        _ tokens: [Token], context: inout EvaluationContext, registry: CurrencyRegistry
    ) throws -> LineResult {
        let statement = try Parser.parse(tokens, registry: registry)
        let evaluator = Evaluator(context: context)
        var isTotal = false
        var quantity: Quantity
        switch statement {
        case .empty:
            return .empty
        case .expression(let expr, let target):
            isTotal = expr == .sum
            quantity = try evaluator.evaluate(expr)
            if let target { quantity = try evaluator.convert(quantity, to: target) }
        case .assignment(let name, let expr, let target):
            quantity = try evaluator.evaluate(expr)
            if let target { quantity = try evaluator.convert(quantity, to: target) }
            context.variables[name] = quantity
        }
        context.previous = quantity
        if !isTotal { context.blockResults.append(quantity) }
        return LineResult(quantity: quantity, isTotal: isTotal)
    }

    /// Number of leading identifiers that are plain words: not keywords, functions, constants,
    /// currencies or defined variables.
    private static func leadingLabelCount(_ tokens: [Token], context: EvaluationContext, registry: CurrencyRegistry) -> Int {
        var n = 0
        for t in tokens {
            guard case .identifier(let w) = t.kind, !Keywords.isReserved(w),
                  !Keywords.constants.contains(w.lowercased()), registry.code(forAlias: w) == nil,
                  context.variables[w] == nil else { break }
            n += 1
        }
        return n
    }
}
