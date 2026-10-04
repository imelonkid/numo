import Foundation

public enum QuantityUnit: Sendable, Equatable {
    case none
    case percent
    case currency(String)
}

public enum DisplayStyle: Sendable, Equatable {
    case standard
    case radix(Radix)
    case scientific
}

/// A number with an optional unit. Currency amounts and percentages are both quantities.
public struct Quantity: Sendable, Equatable {
    public var value: Decimal
    public var unit: QuantityUnit
    public var style: DisplayStyle

    public init(_ value: Decimal, _ unit: QuantityUnit = .none, style: DisplayStyle = .standard) {
        self.value = value
        self.unit = unit
        self.style = style
    }

    var isPercent: Bool { unit == .percent }
    var currencyCode: String? {
        if case .currency(let c) = unit { return c }
        return nil
    }
}

public enum EvalError: Error, Equatable, Sendable, LocalizedError {
    case divisionByZero
    case unknownVariable(String)
    case incompatibleUnits
    case missingRate(String)
    case domain
    case overflow
    case noPrevious

    public var errorDescription: String? {
        switch self {
        case .divisionByZero: return "除数不能为零"
        case .unknownVariable(let n): return "未定义：\(n)"
        case .incompatibleUnits: return "单位不兼容"
        case .missingRate(let c): return "缺少 \(c) 的汇率"
        case .domain: return "超出定义域"
        case .overflow: return "数值过大"
        case .noPrevious: return "上方没有结果"
        }
    }
}

public struct EvaluationContext: Sendable {
    public var variables: [String: Quantity] = [:]
    public var previous: Quantity?
    /// Results in the current block (since the last blank line), used by `sum`.
    public var blockResults: [Quantity] = []
    public var rates: ExchangeRates

    public init(rates: ExchangeRates) {
        self.rates = rates
    }
}

public struct Evaluator {
    public var context: EvaluationContext

    public init(context: EvaluationContext) {
        self.context = context
    }

    public func evaluate(_ expr: Expr) throws -> Quantity {
        switch expr {
        case .number(let v):
            return Quantity(v)

        case .variable(let name):
            if let q = context.variables[name] { return q }
            switch name.lowercased() {
            case "pi", "π": return Quantity(.pi)
            case "tau", "τ": return Quantity(.pi * 2)
            case "e": return Quantity(Decimal(string: "2.71828182845904523536028747135266249775")!)
            default: throw EvalError.unknownVariable(name)
            }

        case .previous:
            guard let p = context.previous else { throw EvalError.noPrevious }
            return p

        case .sum:
            var total = Quantity(0)
            for q in context.blockResults where !q.isPercent {
                total = try add(total, Quantity(q.value, q.unit), sign: 1)
            }
            return total

        case .negate(let e):
            var q = try evaluate(e)
            q.value = -q.value
            return q

        case .percent(let e):
            let q = try evaluate(e)
            guard q.unit == .none else { throw EvalError.incompatibleUnits }
            return Quantity(q.value, .percent)

        case .factorial(let e):
            let q = try plain(evaluate(e))
            guard q.value >= 0, q.value.isInteger, q.value <= 1000 else { throw EvalError.domain }
            var r: Decimal = 1
            var i: Decimal = 2
            while i <= q.value {
                r *= i
                i += 1
            }
            return Quantity(try checked(r))

        case .degrees(let e):
            let q = try plain(evaluate(e))
            return Quantity(q.value * .pi / 180)

        case .currency(let e, let code):
            let q = try evaluate(e)
            switch q.unit {
            case .none: return Quantity(q.value, .currency(code))
            case .currency(let from): return Quantity(try context.rates.convert(q.value, from: from, to: code), .currency(code))
            case .percent: throw EvalError.incompatibleUnits
            }

        case .call(let name, let e):
            return try call(name, evaluate(e))

        case .binary(let op, let l, let r):
            let a = try evaluate(l)
            let b = try evaluate(r)
            switch op {
            case .add: return try add(a, b, sign: 1)
            case .subtract: return try add(a, b, sign: -1)
            case .multiply: return try multiply(a, b)
            case .divide: return try divide(a, b)
            case .power: return try power(a, b)
            case .modulo: return try modulo(a, b)
            case .percentOf:
                guard a.isPercent, !b.isPercent else { throw EvalError.incompatibleUnits }
                return Quantity(try checked(b.value * a.value / 100), b.unit)
            }
        }
    }

    public func convert(_ q: Quantity, to target: ConversionTarget) throws -> Quantity {
        switch target {
        case .currency(let code):
            switch q.unit {
            case .none: return Quantity(q.value, .currency(code))
            case .currency(let from): return Quantity(try context.rates.convert(q.value, from: from, to: code), .currency(code))
            case .percent: throw EvalError.incompatibleUnits
            }
        case .percent:
            switch q.unit {
            case .none: return Quantity(q.value * 100, .percent)
            case .percent: return q
            case .currency: throw EvalError.incompatibleUnits
            }
        case .radix(let r):
            guard q.unit == .none else { throw EvalError.incompatibleUnits }
            if r == .decimal { return Quantity(q.value) }
            guard q.value.isInteger, abs(q.value) <= Decimal(Int64.max) else { throw EvalError.domain }
            return Quantity(q.value, style: .radix(r))
        case .scientific:
            return Quantity(q.value, q.unit, style: .scientific)
        }
    }

    // MARK: Arithmetic with units

    private func add(_ a: Quantity, _ b: Quantity, sign: Decimal) throws -> Quantity {
        switch (a.unit, b.unit) {
        case (.none, .none), (.percent, .percent):
            return Quantity(try checked(a.value + sign * b.value), a.unit)
        case (_, .percent):
            // 200 + 10% → 220
            return Quantity(try checked(a.value * (1 + sign * b.value / 100)), a.unit)
        case (.percent, _):
            throw EvalError.incompatibleUnits
        case (.currency(let c), .currency(let d)):
            let bv = try context.rates.convert(b.value, from: d, to: c)
            return Quantity(try checked(a.value + sign * bv), a.unit)
        case (.currency, .none):
            return Quantity(try checked(a.value + sign * b.value), a.unit)
        case (.none, .currency):
            return Quantity(try checked(a.value + sign * b.value), b.unit)
        }
    }

    private func multiply(_ a: Quantity, _ b: Quantity) throws -> Quantity {
        switch (a.unit, b.unit) {
        case (.none, .none):
            return Quantity(try checked(a.value * b.value))
        case (.percent, .percent):
            return Quantity(try checked(a.value * b.value / 100), .percent)
        case (_, .percent):
            return Quantity(try checked(a.value * b.value / 100), a.unit)
        case (.percent, _):
            return Quantity(try checked(a.value * b.value / 100), b.unit)
        case (.currency, .none):
            return Quantity(try checked(a.value * b.value), a.unit)
        case (.none, .currency):
            return Quantity(try checked(a.value * b.value), b.unit)
        case (.currency, .currency):
            throw EvalError.incompatibleUnits
        }
    }

    private func divide(_ a: Quantity, _ b: Quantity) throws -> Quantity {
        guard !b.value.isZero else { throw EvalError.divisionByZero }
        switch (a.unit, b.unit) {
        case (.none, .none), (.percent, .percent):
            return Quantity(try checked(a.value / b.value))
        case (_, .percent):
            // 50 / 10% → 500
            return Quantity(try checked(a.value / (b.value / 100)), a.unit)
        case (.percent, .none):
            return Quantity(try checked(a.value / b.value), .percent)
        case (.currency(let c), .currency(let d)):
            let bv = try context.rates.convert(b.value, from: d, to: c)
            guard !bv.isZero else { throw EvalError.divisionByZero }
            return Quantity(try checked(a.value / bv))
        case (.currency, .none):
            return Quantity(try checked(a.value / b.value), a.unit)
        case (.none, .currency), (.percent, .currency):
            throw EvalError.incompatibleUnits
        }
    }

    private func modulo(_ a: Quantity, _ b: Quantity) throws -> Quantity {
        var bv = b.value
        switch (a.unit, b.unit) {
        case (.none, .none), (.currency, .none), (.percent, .percent):
            break
        case (.currency(let c), .currency(let d)):
            bv = try context.rates.convert(b.value, from: d, to: c)
        default:
            throw EvalError.incompatibleUnits
        }
        guard !bv.isZero else { throw EvalError.divisionByZero }
        let q = (a.value / bv).rounded(0, .down)
        return Quantity(try checked(a.value - bv * q), a.unit)
    }

    private func power(_ a: Quantity, _ b: Quantity) throws -> Quantity {
        let base = try plain(a).value
        let exp = try plain(b).value
        if exp.isInteger, abs(exp) <= 10_000 {
            let n = NSDecimalNumber(decimal: exp).intValue
            if base.isZero && n < 0 { throw EvalError.divisionByZero }
            let r = pow(base, abs(n))
            return Quantity(try checked(n < 0 ? 1 / r : r))
        }
        guard base >= 0 else { throw EvalError.domain }
        return Quantity(try decimal(Foundation.pow(base.doubleValue, exp.doubleValue)))
    }

    private func call(_ name: String, _ q: Quantity) throws -> Quantity {
        switch name {
        case "abs":
            return Quantity(abs(q.value), q.unit)
        case "round":
            return Quantity(q.value.rounded(0, .plain), q.unit)
        case "floor":
            return Quantity(q.value.rounded(0, .down), q.unit)
        case "ceil":
            return Quantity(q.value.rounded(0, .up), q.unit)
        default:
            break
        }

        let x = try plain(q).value
        let d = x.doubleValue
        let result: Double
        switch name {
        case "sqrt":
            guard d >= 0 else { throw EvalError.domain }
            result = d.squareRoot()
        case "cbrt": result = Foundation.cbrt(d)
        case "sin": result = Foundation.sin(d)
        case "cos": result = Foundation.cos(d)
        case "tan": result = Foundation.tan(d)
        case "asin", "arcsin":
            guard abs(d) <= 1 else { throw EvalError.domain }
            result = Foundation.asin(d)
        case "acos", "arccos":
            guard abs(d) <= 1 else { throw EvalError.domain }
            result = Foundation.acos(d)
        case "atan", "arctan": result = Foundation.atan(d)
        case "sinh": result = Foundation.sinh(d)
        case "cosh": result = Foundation.cosh(d)
        case "tanh": result = Foundation.tanh(d)
        case "ln", "log", "log2", "log10":
            guard d > 0 else { throw EvalError.domain }
            switch name {
            case "ln": result = Foundation.log(d)
            case "log2": result = Foundation.log2(d)
            default: result = Foundation.log10(d)
            }
        case "exp": result = Foundation.exp(d)
        default: throw EvalError.unknownVariable(name)
        }
        return Quantity(try decimal(result))
    }

    /// Strips percent (→ fraction) and rejects currencies, for purely numeric operations.
    private func plain(_ q: Quantity) throws -> Quantity {
        switch q.unit {
        case .none: return q
        case .percent: return Quantity(q.value / 100)
        case .currency: throw EvalError.incompatibleUnits
        }
    }
}

// MARK: - Decimal helpers

func checked(_ d: Decimal) throws -> Decimal {
    if d.isNaN { throw EvalError.overflow }
    return d
}

/// Converts a Double result back to Decimal, keeping 15 significant digits to drop float noise.
func decimal(_ d: Double) throws -> Decimal {
    guard d.isFinite else { throw EvalError.domain }
    var s = String(format: "%.15g", d)
    s = s.replacingOccurrences(of: "e+", with: "e")
    guard let v = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else { throw EvalError.overflow }
    return v
}

extension Decimal {
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    func rounded(_ scale: Int, _ mode: NSDecimalNumber.RoundingMode) -> Decimal {
        var v = self
        var r = Decimal()
        NSDecimalRound(&r, &v, scale, mode)
        return r
    }

    var isInteger: Bool { !isNaN && self == rounded(0, .down) }
}
