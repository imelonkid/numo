import Foundation
import Testing
@testable import NumoCore

private let testRates = ExchangeRates(base: "USD", rates: ["CNY": 7, "EUR": 0.5, "JPY": 150])

/// Evaluates a document and returns each line's displayed result ("" for no result).
private func run(_ lines: [String]) -> [String] {
    Document.evaluate(lines, rates: testRates).map { r in
        r.quantity.map { QuantityFormatter.display($0) } ?? ""
    }
}

private func calc(_ line: String) -> String { run([line])[0] }

@Suite struct ArithmeticTests {
    @Test(arguments: [
        ("1+1", "2"),
        ("1 + 2 * 3", "7"),
        ("(1+2)*3", "9"),
        ("2^10", "1,024"),
        ("2**3", "8"),
        ("2^3^2", "512"),
        ("-2^2", "-4"),
        ("2^-1", "0.5"),
        ("10 / 4", "2.5"),
        ("1/3", "0.3333"),
        ("0.1 + 0.2", "0.3"),
        ("10 mod 3", "1"),
        ("-7 mod 3", "2"),
        ("5!", "120"),
        ("3 × 4 ÷ 2", "6"),
        ("１＋１", "2"),
        ("1,000 + 1", "1,001"),
        ("1e3", "1,000"),
        (".5 * 2", "1"),
        ("2(3+4)", "14"),
        ("(1+2", "3"),
        ("1+1=", "2"),
        ("0xFF", "255"),
        ("0b1010 + 1", "11"),
        ("299 × 0.85", "254.15"),
        ("5 − 2", "3"),
        ("2××3", "8"),
        ("1e−3 * 1000", "1"),
    ])
    func arithmetic(_ input: String, _ expected: String) {
        #expect(calc(input) == expected)
    }

    @Test func divisionByZeroHasNoResult() {
        let r = Document.evaluate(["1/0"], rates: testRates)[0]
        #expect(r.quantity == nil)
        #expect(r.error == "除数不能为零")
    }

    @Test func garbageHasNoResult() {
        #expect(calc("hello world") == "")
        #expect(calc("1 +") == "")
        #expect(calc("3 4") == "")
    }

    @Test func decimalsAreConfigurable() {
        let third = Quantity(Decimal(1) / Decimal(3))
        #expect(QuantityFormatter.display(third, decimals: 0) == "0")
        #expect(QuantityFormatter.display(Quantity(Decimal(string: "2.5")!), decimals: 0) == "3")
        #expect(QuantityFormatter.display(third, decimals: 2) == "0.33")
        #expect(QuantityFormatter.display(third, decimals: 8) == "0.33333333")
        #expect(QuantityFormatter.display(Quantity(Decimal(string: "1.5")!), decimals: 8) == "1.5")
        #expect(QuantityFormatter.display(Quantity(Decimal(string: "0.00001234")!)) == "1.234e-5")
        #expect(QuantityFormatter.display(Quantity(1234, .currency("CNY")), decimals: 0) == "¥1,234.00")
        #expect(QuantityFormatter.copyText(third, decimals: 2) == "0.33")
    }

    @Test func hugeNumbersUseScientific() {
        #expect(calc("10^20") == "1e20")
        #expect(calc("2^0.5 * 10^-12") == "1.414213562e-12")
    }
}

@Suite struct FunctionTests {
    @Test(arguments: [
        ("√π", "1.7725"),
        ("√16", "4"),
        ("√(2+2)", "2"),
        ("sqrt 16 + 1", "5"),
        ("sqrt(16)^2", "16"),
        ("∛27", "3"),
        ("2π", "6.2832"),
        ("pi", "3.1416"),
        ("e", "2.7183"),
        ("sin 30°", "0.5"),
        ("cos(60°) * 2", "1"),
        ("sin(π/2)", "1"),
        ("log 1000", "3"),
        ("ln e", "1"),
        ("log2 8", "3"),
        ("abs -3", "3"),
        ("round 3.6", "4"),
        ("floor -1.5", "-2"),
        ("ceil 1.2", "2"),
    ])
    func functions(_ input: String, _ expected: String) {
        #expect(calc(input) == expected)
    }

    @Test func domainErrors() {
        #expect(calc("√-1") == "")
        #expect(calc("ln 0") == "")
    }
}

@Suite struct PercentTests {
    @Test(arguments: [
        ("10%", "10%"),
        ("200 + 10%", "220"),
        ("200 - 25%", "150"),
        ("20% of 150", "30"),
        ("50 * 10%", "5"),
        ("50 / 10%", "500"),
        ("0.25 to %", "25%"),
        ("50 / 200 in %", "25%"),
    ])
    func percent(_ input: String, _ expected: String) {
        #expect(calc(input) == expected)
    }
}

@Suite struct CurrencyTests {
    @Test(arguments: [
        ("1$", "$1.00"),
        ("$100", "$100.00"),
        ("1$ to ¥", "¥7.00"),
        ("1$=¥", "¥7.00"),
        ("1$=?¥", "¥7.00"),
        ("1$ = ¥", "¥7.00"),
        ("100 usd in cny", "¥700.00"),
        ("100 USD to EUR", "€50.00"),
        ("10€ → $", "$20.00"),
        ("10€ −> $", "$20.00"),
        ("100美元换成人民币", "¥700.00"),
        ("100 美元 to 元", "¥700.00"),
        ("700元 to 美元", "$100.00"),
        ("1$ + 7¥", "$2.00"),
        ("100$ * 2", "$200.00"),
        ("100$ / 4$", "25"),
        ("100$ + 10%", "$110.00"),
        ("20% of 50$", "$10.00"),
        ("1000 jpy to usd", "$6.67"),
        ("1 usd to jpy", "JP¥150"),
        ("-5$", "-$5.00"),
        ("1234567.891 ¥", "¥1,234,567.89"),
        ("5 to $", "$5.00"),
        ("0.001$", "$0.001"),
    ])
    func currency(_ input: String, _ expected: String) {
        #expect(calc(input) == expected)
    }

    @Test func incompatible() {
        #expect(calc("1$ * 1$") == "")
        #expect(calc("1 / 1$") == "")
    }

    @Test func missingRate() {
        let r = Document.evaluate(["1 chf to $"], rates: testRates)[0]
        #expect(r.error == "缺少 CHF 的汇率")
    }

    @Test func copyTextIsPlain() {
        let q = Quantity(Decimal(string: "1234.5")!, .currency("CNY"))
        #expect(QuantityFormatter.copyText(q) == "1234.50")
        #expect(QuantityFormatter.copyText(Quantity(25, .percent)) == "25%")
    }
}

@Suite struct DocumentTests {
    @Test func variablesAndPrev() {
        let out = run([
            "价格 = 299 * 0.85",
            "价格 * 3",
            "prev + 0.55",
            "a = 2",
            "a ^ 2",
        ])
        #expect(out == ["254.15", "762.45", "763", "2", "4"])
    }

    @Test func sumResetsOnBlankLine() {
        let out = run([
            "1",
            "2",
            "sum",
            "",
            "10",
            "total",
        ])
        #expect(out == ["1", "2", "3", "", "10", "10"])
    }

    @Test func sumConvertsCurrencies() {
        #expect(run(["房租: 1000¥", "餐饮: 100$", "合计"]) == ["¥1,000.00", "$100.00", "¥1,700.00"])
    }

    @Test func commentsAndLabels() {
        let out = run([
            "# 标题",
            "Rent: 3000",
            "1 + 1 // note",
            "Food: 500",
            "sum",
        ])
        #expect(out == ["", "3,000", "2", "500", "3,502"])
    }

    @Test func plainWordLabels() {
        let r = Document.evaluate(["房租 3000¥", "Food 500$ to ¥", "餐饮 200$", "合计"], rates: testRates)
        #expect(r.map { $0.quantity.map { QuantityFormatter.display($0) } ?? "" } == ["¥3,000.00", "¥3,500.00", "$200.00", "¥7,900.00"])
        #expect(r[0].label == 0..<2)
        #expect(r[1].label == 0..<4)
        #expect(r[3].isTotal)
        #expect(!r[0].isTotal)
    }

    @Test func colonLabelIsReported() {
        #expect(Document.evaluate(["Rent: 3000"], rates: testRates)[0].label == 0..<5)
    }

    @Test func variablesAreNotLabels() {
        #expect(run(["a = 2", "a 3"]) == ["2", ""])  // not "3": a defined variable is never a label
    }

    @Test func radixAndScientific() {
        #expect(calc("255 in hex") == "0xFF")
        #expect(calc("10 to bin") == "0b1010")
        #expect(calc("8 to oct") == "0o10")
        #expect(calc("1234 to sci") == "1.234e3")
        #expect(calc("1.5 to hex") == "")
    }

    @Test func assignmentWithConversion() {
        #expect(run(["x = 10$ to ¥", "x * 2"]) == ["¥70.00", "¥140.00"])
    }

    @Test func constantsCanBeShadowed() {
        #expect(run(["e = 5", "e * 2"]) == ["5", "10"])
    }
}

@Suite struct LexerTests {
    @Test func cjkSplitting() {
        let kinds = Lexer.tokenize("100美元换成人民币").map(\.kind)
        #expect(kinds == [.number(100), .identifier("美元"), .identifier("换成"), .identifier("人民币")])
    }

    @Test func rangesAreUTF16() {
        let tokens = Lexer.tokenize("价格 = 1")
        #expect(tokens.map(\.range) == [0..<2, 3..<4, 5..<6])
    }

    @Test func highlightOffsetsIncludeLabel() {
        let h = Highlighter.highlights(for: "Rent: 3$ // x")
        #expect(h.map(\.kind) == [.label, .number, .unit, .comment])
        #expect(h[1].range == 6..<7)
    }
}
