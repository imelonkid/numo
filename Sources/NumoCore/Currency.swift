import Foundation

public struct Currency: Sendable, Equatable {
    public let code: String
    /// Prefix shown before the amount, e.g. "$". `nil` means the code is shown after the amount.
    public let symbol: String?
    public let fractionDigits: Int
    public let aliases: [String]

    public init(_ code: String, symbol: String? = nil, fractionDigits: Int = 2, aliases: [String] = []) {
        self.code = code
        self.symbol = symbol
        self.fractionDigits = fractionDigits
        self.aliases = aliases
    }
}

/// Knows which words and symbols refer to which currency.
public struct CurrencyRegistry: Sendable {
    public let currencies: [String: Currency]
    private let aliasToCode: [String: String]
    private let symbolToCode: [Unicode.Scalar: String]
    /// Aliases written in CJK characters; the lexer uses them to split runs like "100美元换成人民币".
    public let cjkAliases: Set<String>

    /// - Parameter yenSymbolCode: what a bare "¥" means. Defaults to CNY.
    public init(currencies list: [Currency], yenSymbolCode: String = "CNY") {
        var currencies: [String: Currency] = [:]
        var aliases: [String: String] = [:]
        var cjk: Set<String> = []
        for c in list {
            currencies[c.code] = c
            aliases[c.code.lowercased()] = c.code
            for a in c.aliases {
                aliases[a.lowercased()] = c.code
                if a.unicodeScalars.contains(where: { $0.properties.isIdeographic }) { cjk.insert(a) }
            }
        }
        self.currencies = currencies
        self.aliasToCode = aliases
        self.cjkAliases = cjk
        self.symbolToCode = [
            "$": "USD", "¥": yenSymbolCode, "￥": yenSymbolCode, "€": "EUR", "£": "GBP",
            "₩": "KRW", "₹": "INR", "₽": "RUB", "฿": "THB", "₺": "TRY", "₫": "VND",
            "₱": "PHP", "₪": "ILS",
        ]
    }

    public func code(forAlias word: String) -> String? { aliasToCode[word.lowercased()] }
    public func code(forSymbol scalar: Unicode.Scalar) -> String? { symbolToCode[scalar] }
    public func currency(_ code: String) -> Currency? { currencies[code] }

    public static let standard = CurrencyRegistry(currencies: [
        Currency("USD", symbol: "$", aliases: ["dollar", "dollars", "usd", "美元", "美金"]),
        Currency("CNY", symbol: "¥", aliases: ["rmb", "yuan", "人民币", "元", "块"]),
        Currency("EUR", symbol: "€", aliases: ["euro", "euros", "欧元"]),
        Currency("GBP", symbol: "£", aliases: ["pound", "pounds", "英镑"]),
        Currency("JPY", symbol: "JP¥", fractionDigits: 0, aliases: ["yen", "日元", "円"]),
        Currency("HKD", symbol: "HK$", aliases: ["港币", "港元"]),
        Currency("TWD", symbol: "NT$", aliases: ["台币", "新台币"]),
        Currency("KRW", symbol: "₩", fractionDigits: 0, aliases: ["won", "韩元"]),
        Currency("INR", symbol: "₹", aliases: ["rupee", "rupees", "卢比"]),
        Currency("RUB", symbol: "₽", aliases: ["ruble", "rubles", "卢布"]),
        Currency("AUD", symbol: "A$", aliases: ["澳元"]),
        Currency("CAD", symbol: "CA$", aliases: ["加元"]),
        Currency("SGD", symbol: "S$", aliases: ["新加坡元", "新币"]),
        Currency("NZD", symbol: "NZ$", aliases: ["纽币"]),
        Currency("CHF", aliases: ["瑞郎", "瑞士法郎"]),
        Currency("THB", symbol: "฿", aliases: ["baht", "泰铢"]),
        Currency("MYR", aliases: ["ringgit", "马币", "令吉"]),
        Currency("VND", symbol: "₫", fractionDigits: 0, aliases: ["越南盾"]),
        Currency("PHP", symbol: "₱", aliases: ["比索"]),
        Currency("IDR", fractionDigits: 0, aliases: ["印尼盾"]),
        Currency("TRY", symbol: "₺", aliases: ["lira", "里拉"]),
        Currency("ILS", symbol: "₪", aliases: ["shekel", "谢克尔"]),
        Currency("BRL", symbol: "R$", aliases: ["real", "雷亚尔"]),
        Currency("MXN", symbol: "MX$", aliases: ["墨西哥比索"]),
        Currency("ZAR", aliases: ["rand", "兰特"]),
        Currency("AED", aliases: ["dirham", "迪拉姆"]),
        Currency("SAR", aliases: ["riyal", "里亚尔"]),
        Currency("SEK", aliases: ["瑞典克朗"]),
        Currency("NOK", aliases: ["挪威克朗"]),
        Currency("DKK", aliases: ["丹麦克朗"]),
        Currency("PLN", aliases: ["zloty", "兹罗提"]),
        Currency("MOP", aliases: ["澳门币", "澳门元"]),
    ])
}

/// Exchange rates expressed as "units of currency per 1 unit of `base`".
public struct ExchangeRates: Sendable, Codable, Equatable {
    public var base: String
    public var rates: [String: Decimal]
    public var updatedAt: Date?
    /// True when these are the built-in approximate rates rather than fetched ones.
    public var isFallback: Bool

    public init(base: String, rates: [String: Decimal], updatedAt: Date? = nil, isFallback: Bool = false) {
        self.base = base
        self.rates = rates
        self.updatedAt = updatedAt
        self.isFallback = isFallback
    }

    public func convert(_ amount: Decimal, from: String, to: String) throws -> Decimal {
        if from == to { return amount }
        guard let fromRate = rate(from) else { throw EvalError.missingRate(from) }
        guard let toRate = rate(to) else { throw EvalError.missingRate(to) }
        return amount / fromRate * toRate
    }

    private func rate(_ code: String) -> Decimal? {
        if code == base { return 1 }
        guard let r = rates[code], r > 0 else { return nil }
        return r
    }

    /// Rough rates used before the first successful fetch, so the app works offline from day one.
    public static let fallback = ExchangeRates(base: "USD", rates: [
        "USD": 1, "CNY": 7.12, "EUR": 0.86, "GBP": 0.75, "JPY": 148, "HKD": 7.78,
        "TWD": 30.5, "KRW": 1390, "INR": 88, "RUB": 82, "AUD": 1.52, "CAD": 1.39,
        "SGD": 1.29, "NZD": 1.72, "CHF": 0.8, "THB": 32.5, "MYR": 4.21, "VND": 26300,
        "PHP": 58, "IDR": 16600, "TRY": 41.6, "ILS": 3.3, "BRL": 5.33, "MXN": 18.4,
        "ZAR": 17.4, "AED": 3.6725, "SAR": 3.75, "SEK": 9.4, "NOK": 10, "DKK": 6.4,
        "PLN": 3.64, "MOP": 8.01,
    ], isFallback: true)
}
