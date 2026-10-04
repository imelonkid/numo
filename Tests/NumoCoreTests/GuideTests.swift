import Foundation
import Testing
@testable import NumoCore

@Suite struct GuideTests {
    private let rates = ExchangeRates(base: "USD", rates: ["CNY": 7, "EUR": 0.5, "JPY": 150])

    @Test(arguments: [Guide.text, Guide.welcome])
    func everyExampleLineEvaluates(_ text: String) {
        let lines = text.components(separatedBy: "\n")
        let results = Document.evaluate(lines, rates: rates)
        for (line, result) in zip(lines, results) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                #expect(result.quantity == nil, "comment produced a result: \(line)")
            } else {
                #expect(result.quantity != nil, "no result for: \(line) — \(result.error ?? "")")
            }
        }
    }

    @Test func selectedResults() {
        let lines = Guide.text.components(separatedBy: "\n")
        let results = Document.evaluate(lines, rates: rates)
        func result(_ prefix: String) -> String? {
            guard let i = lines.firstIndex(where: { $0.hasPrefix(prefix) }) else { return nil }
            return results[i].quantity.map { QuantityFormatter.display($0) }
        }
        #expect(result("1 + 2 × 3") == "7")
        #expect(result("0.1 + 0.2") == "0.3")
        #expect(result("1,000,000 ÷ 4") == "250,000")
        #expect(result("abs(−8)") == "8")
        #expect(result("200 − 25%") == "150")
        #expect(result("50€ + 20$") == "€60.00")
        #expect(result("prev − 10%") == "686.205")
        #expect(result("0xFF + 0b1010") == "265")
        #expect(result("合计") == "¥4,660.00")
    }

    @Test func welcomeEndsWithTotal() {
        let lines = Guide.welcome.components(separatedBy: "\n")
        let results = Document.evaluate(lines, rates: rates)
        let i = lines.firstIndex(of: "合计")!
        #expect(results[i].isTotal)
        #expect(results[i].quantity.map { QuantityFormatter.display($0) } == "¥4,400.00")
    }
}
