import Foundation

public enum BinaryOp: Sendable, Equatable {
    case add, subtract, multiply, divide, power, modulo
    /// "20% of 150"
    case percentOf
}

public indirect enum Expr: Sendable, Equatable {
    case number(Decimal)
    case variable(String)
    case negate(Expr)
    case binary(BinaryOp, Expr, Expr)
    case percent(Expr)
    case factorial(Expr)
    case degrees(Expr)
    case currency(Expr, String)
    case call(String, Expr)
    case previous
    case sum
}

public enum Radix: Sendable, Equatable {
    case hex, binary, octal, decimal
}

public enum ConversionTarget: Sendable, Equatable {
    case currency(String)
    case percent
    case radix(Radix)
    case scientific
}

public enum Statement: Sendable, Equatable {
    case empty
    case expression(Expr, ConversionTarget?)
    case assignment(String, Expr, ConversionTarget?)
}

enum Keywords {
    static let conversion: Set<String> = ["to", "in", "as", "into", "换成", "转成", "兑换成", "转换成", "换算成", "等于"]
    static let sum: Set<String> = ["sum", "total", "合计", "总计", "求和"]
    static let previous: Set<String> = ["prev", "previous", "ans", "上一行"]
    static let functions: Set<String> = [
        "sqrt", "cbrt", "sin", "cos", "tan", "asin", "acos", "atan", "arcsin", "arccos", "arctan",
        "sinh", "cosh", "tanh", "ln", "log", "log2", "log10", "exp", "abs", "round", "floor", "ceil",
    ]
    static let constants: Set<String> = ["pi", "π", "e", "tau", "τ"]
    static let radixTargets: [String: ConversionTarget] = [
        "hex": .radix(.hex), "hexadecimal": .radix(.hex), "十六进制": .radix(.hex),
        "bin": .radix(.binary), "binary": .radix(.binary), "二进制": .radix(.binary),
        "oct": .radix(.octal), "octal": .radix(.octal), "八进制": .radix(.octal),
        "dec": .radix(.decimal), "decimal": .radix(.decimal), "十进制": .radix(.decimal),
        "sci": .scientific, "scientific": .scientific, "科学计数法": .scientific,
    ]

    static func isConversion(_ word: String) -> Bool { conversion.contains(word.lowercased()) }
    static func isReserved(_ word: String) -> Bool {
        let w = word.lowercased()
        return conversion.contains(w) || sum.contains(w) || previous.contains(w) || functions.contains(w)
            || w == "of" || w == "mod" || w == "pi" || w == "π"
    }
}

public struct ParseError: Error, Equatable, Sendable {
    public let message: String
}

/// Pratt parser over the token stream of a single line.
public struct Parser {
    private let tokens: [Token]
    private let registry: CurrencyRegistry
    private var pos = 0

    public static func parse(_ tokens: [Token], registry: CurrencyRegistry = .standard) throws -> Statement {
        var p = Parser(tokens: tokens, registry: registry)
        return try p.parseStatement()
    }

    private init(tokens: [Token], registry: CurrencyRegistry) {
        self.tokens = tokens
        self.registry = registry
    }

    // MARK: Binding powers

    private enum BP {
        static let additive = 10
        static let multiplicative = 20
        static let unary = 30
        static let functionArgument = 35
        static let power = 40
        static let postfix = 50
    }

    // MARK: Statement

    private mutating func parseStatement() throws -> Statement {
        if tokens.isEmpty { return .empty }

        // Assignment: name = expr
        if tokens.count >= 2, case .identifier(let name) = tokens[0].kind, tokens[1].kind == .symbol("="),
           !Keywords.isReserved(name), registry.code(forAlias: name) == nil {
            pos = 2
            let expr = try parseExpression(0)
            let target = try parseConversionTail()
            try expectEnd()
            return .assignment(name, expr, target)
        }

        let expr = try parseExpression(0)
        let target = try parseConversionTail()
        try expectEnd()
        return .expression(expr, target)
    }

    /// "to ¥", "in usd", "= ¥", "=?¥", "→ hex", or a trailing "=".
    private mutating func parseConversionTail() throws -> ConversionTarget? {
        guard let t = peek else { return nil }
        switch t.kind {
        case .symbol("="), .symbol("→"):
            break
        case .identifier(let w) where Keywords.isConversion(w):
            break
        default:
            return nil
        }
        advance()
        while peek?.kind == .symbol("?") { advance() }
        guard let target = peek else { return nil }
        advance()
        switch target.kind {
        case .currency(let code):
            return .currency(code)
        case .symbol("%"):
            return .percent
        case .identifier(let w):
            if let code = registry.code(forAlias: w) { return .currency(code) }
            if let r = Keywords.radixTargets[w.lowercased()] { return r }
            throw ParseError(message: "无法换算为 \(w)")
        default:
            throw ParseError(message: "缺少换算目标")
        }
    }

    private func expectEnd() throws {
        // Allow a trailing "=" or "=?" after everything, e.g. "1+1=".
        var p = pos
        while p < tokens.count, tokens[p].kind == .symbol("=") || tokens[p].kind == .symbol("?") { p += 1 }
        if p < tokens.count { throw ParseError(message: "无法识别的内容") }
    }

    // MARK: Expressions

    private var peek: Token? { pos < tokens.count ? tokens[pos] : nil }
    private mutating func advance() { pos += 1 }

    private mutating func parseExpression(_ minBP: Int) throws -> Expr {
        var lhs = try parsePrefix()
        while let t = peek {
            let bp = leftBindingPower(t)
            if bp <= minBP { break }
            lhs = try parseInfix(lhs, t)
        }
        return lhs
    }

    private mutating func parsePrefix() throws -> Expr {
        guard let t = peek else { throw ParseError(message: "表达式不完整") }
        advance()
        switch t.kind {
        case .number(let v):
            return .number(v)
        case .currency(let code):
            // "$100"
            return .currency(try parseExpression(BP.power), code)
        case .symbol("("):
            return try parseGroup()
        case .symbol("-"):
            return .negate(try parseExpression(BP.unary))
        case .symbol("+"):
            return try parseExpression(BP.unary)
        case .symbol("√"):
            return .call("sqrt", try parseFunctionArgument())
        case .symbol("∛"):
            return .call("cbrt", try parseFunctionArgument())
        case .identifier(let name):
            let lower = name.lowercased()
            if Keywords.functions.contains(lower) {
                return .call(lower, try parseFunctionArgument())
            }
            if Keywords.sum.contains(lower) { return .sum }
            if Keywords.previous.contains(lower) { return .previous }
            if let code = registry.code(forAlias: name) {
                // "usd 100"
                return .currency(try parseExpression(BP.power), code)
            }
            if Keywords.isConversion(name) || lower == "of" || lower == "mod" {
                throw ParseError(message: "意外的 \(name)")
            }
            return .variable(name)
        default:
            throw ParseError(message: "无法识别的符号")
        }
    }

    /// Parses after "(" has been consumed. A missing ")" at end of line is tolerated while typing.
    private mutating func parseGroup() throws -> Expr {
        let inner = try parseExpression(0)
        if peek?.kind == .symbol(")") {
            advance()
        } else if peek != nil {
            throw ParseError(message: "缺少右括号")
        }
        return inner
    }

    /// `sqrt(16)` binds tightly; `sin 30°` takes the following operand.
    private mutating func parseFunctionArgument() throws -> Expr {
        if peek?.kind == .symbol("(") {
            advance()
            return try parseGroup()
        }
        return try parseExpression(BP.functionArgument)
    }

    private func leftBindingPower(_ t: Token) -> Int {
        switch t.kind {
        case .symbol("+"), .symbol("-"):
            return BP.additive
        case .symbol("*"), .symbol("/"):
            return BP.multiplicative
        case .symbol("^"):
            return BP.power
        case .symbol("%"), .symbol("!"), .symbol("°"), .currency:
            return BP.postfix
        case .symbol("("), .symbol("√"), .symbol("∛"):
            return BP.multiplicative  // implicit multiplication: 2(3+4), 2√3
        case .identifier(let w):
            let lower = w.lowercased()
            if lower == "of" || lower == "mod" { return BP.multiplicative }
            if Keywords.isConversion(w) { return 0 }
            if registry.code(forAlias: w) != nil { return BP.postfix }
            return BP.multiplicative  // implicit multiplication: 2π, 3 x
        default:
            return 0
        }
    }

    private mutating func parseInfix(_ lhs: Expr, _ t: Token) throws -> Expr {
        switch t.kind {
        case .symbol("+"):
            advance()
            return .binary(.add, lhs, try parseExpression(BP.additive))
        case .symbol("-"):
            advance()
            return .binary(.subtract, lhs, try parseExpression(BP.additive))
        case .symbol("*"):
            advance()
            return .binary(.multiply, lhs, try parseExpression(BP.multiplicative))
        case .symbol("/"):
            advance()
            return .binary(.divide, lhs, try parseExpression(BP.multiplicative))
        case .symbol("^"):
            advance()
            return .binary(.power, lhs, try parseExpression(BP.power - 1))  // right-associative
        case .symbol("%"):
            advance()
            return .percent(lhs)
        case .symbol("!"):
            advance()
            return .factorial(lhs)
        case .symbol("°"):
            advance()
            return .degrees(lhs)
        case .currency(let code):
            advance()
            return .currency(lhs, code)
        case .identifier(let w):
            let lower = w.lowercased()
            if lower == "of" {
                advance()
                return .binary(.percentOf, lhs, try parseExpression(BP.multiplicative))
            }
            if lower == "mod" {
                advance()
                return .binary(.modulo, lhs, try parseExpression(BP.multiplicative))
            }
            if let code = registry.code(forAlias: w) {
                advance()
                return .currency(lhs, code)
            }
            return .binary(.multiply, lhs, try parseExpression(BP.multiplicative))
        default:
            // Implicit multiplication with "(" / "√"; the token is consumed by parsePrefix.
            return .binary(.multiply, lhs, try parseExpression(BP.multiplicative))
        }
    }
}
