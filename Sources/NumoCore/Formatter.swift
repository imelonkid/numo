import Foundation

public enum QuantityFormatter {
    /// Maximum decimal places for plain numbers and percentages (currencies use their own, e.g. 2).
    public static let defaultDecimals = 4

    /// Human-readable result, e.g. "1,234.5", "¥718.30", "25%", "0xFF".
    public static func display(_ q: Quantity, decimals: Int = defaultDecimals, registry: CurrencyRegistry = .standard) -> String {
        format(q, decimals: decimals, registry: registry, grouping: true, withUnit: true)
    }

    /// What goes to the clipboard: no thousands separators and no currency symbol, so it pastes cleanly.
    public static func copyText(_ q: Quantity, decimals: Int = defaultDecimals, registry: CurrencyRegistry = .standard) -> String {
        format(q, decimals: decimals, registry: registry, grouping: false, withUnit: q.unit == .percent)
    }

    private static func format(_ q: Quantity, decimals: Int, registry: CurrencyRegistry, grouping: Bool, withUnit: Bool) -> String {
        switch q.style {
        case .radix(let r):
            return radixString(q.value, r)
        case .scientific:
            return scientific(q.value) + (withUnit ? unitSuffix(q.unit) : "")
        case .standard:
            break
        }

        switch q.unit {
        case .none:
            return number(q.value, decimals: decimals, grouping: grouping)
        case .percent:
            return number(q.value, decimals: decimals, grouping: grouping) + (withUnit ? "%" : "")
        case .currency(let code):
            let currency = registry.currency(code)
            let digits = currency?.fractionDigits ?? 2
            var amount = fixed(q.value, digits: digits, grouping: grouping)
            if amount.trimmingCharacters(in: CharacterSet(charactersIn: "-0.,")).isEmpty && !q.value.isZero {
                // Too small for the currency's usual precision; show significant digits instead.
                amount = number(q.value, decimals: max(decimals, digits), grouping: grouping)
            }
            guard withUnit else { return amount }
            if let symbol = currency?.symbol {
                return amount.hasPrefix("-") ? "-" + symbol + amount.dropFirst() : symbol + amount
            }
            return amount + " " + code
        }
    }

    private static func unitSuffix(_ unit: QuantityUnit) -> String {
        switch unit {
        case .none: return ""
        case .percent: return "%"
        case .currency(let c): return " " + c
        }
    }

    /// General number: at most `decimals` decimal places, trailing zeros dropped.
    /// Scientific when very large, or when a tiny value would round to 0 (unless 0 decimals were asked for).
    static func number(_ v: Decimal, decimals: Int, grouping: Bool) -> String {
        if v.isZero { return "0" }
        let a = abs(v)
        if a >= Decimal(sign: .plus, exponent: 15, significand: 1) {
            return scientific(v)
        }
        let r = v.rounded(max(0, decimals), .plain)
        if r.isZero { return decimals > 0 ? scientific(v) : "0" }
        return grouped(plainString(r), grouping: grouping)
    }

    static func fixed(_ v: Decimal, digits: Int, grouping: Bool) -> String {
        var s = plainString(v.rounded(digits, .plain))
        if digits > 0 {
            if !s.contains(".") { s += "." }
            let frac = s.count - (s.firstIndex(of: ".").map { s.distance(from: s.startIndex, to: $0) + 1 } ?? s.count)
            s += String(repeating: "0", count: max(0, digits - frac))
        }
        return grouped(s, grouping: grouping)
    }

    static func scientific(_ v: Decimal) -> String {
        let s = String(format: "%.9e", v.doubleValue)
        let parts = s.split(separator: "e")
        guard parts.count == 2, let exp = Int(parts[1]) else { return s }
        var mantissa = String(parts[0])
        if mantissa.contains(".") {
            while mantissa.hasSuffix("0") { mantissa.removeLast() }
            if mantissa.hasSuffix(".") { mantissa.removeLast() }
        }
        return "\(mantissa)e\(exp)"
    }

    private static func radixString(_ v: Decimal, _ r: Radix) -> String {
        let n = NSDecimalNumber(decimal: v).int64Value
        let magnitude = n.magnitude
        let sign = n < 0 ? "-" : ""
        switch r {
        case .hex: return sign + "0x" + String(magnitude, radix: 16, uppercase: true)
        case .binary: return sign + "0b" + String(magnitude, radix: 2)
        case .octal: return sign + "0o" + String(magnitude, radix: 8)
        case .decimal: return String(n)
        }
    }

    /// Decimal.description never uses exponent notation, which is what we want here.
    private static func plainString(_ v: Decimal) -> String {
        v.description
    }

    private static func grouped(_ s: String, grouping: Bool) -> String {
        guard grouping else { return s }
        var sign = ""
        var body = Substring(s)
        if body.hasPrefix("-") {
            sign = "-"
            body = body.dropFirst()
        }
        let parts = body.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let intPart = Array(parts[0])
        var out = ""
        for (i, ch) in intPart.enumerated() {
            if i > 0 && (intPart.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        if parts.count > 1 { out += "." + parts[1] }
        return sign + out
    }
}
