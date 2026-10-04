import Combine
import Foundation
import NumoCore

/// Fetches exchange rates, caches them on disk, and falls back to built-in rates when offline.
/// Shared by all document windows.
final class RateService: ObservableObject {
    static let shared = RateService()

    @Published private(set) var rates: ExchangeRates

    private let endpoint = URL(string: "https://open.er-api.com/v6/latest/USD")!
    private let refreshInterval: TimeInterval = 6 * 3600
    private var timer: Timer?
    private var isFetching = false

    private static var cacheURL: URL { AppPaths.supportDirectory.appendingPathComponent("rates.json") }

    private init() {
        if let data = try? Data(contentsOf: Self.cacheURL),
           let cached = try? JSONDecoder().decode(ExchangeRates.self, from: data) {
            rates = cached
        } else {
            rates = .fallback
        }
    }

    func start() {
        refreshIfStale()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.refreshIfStale()
        }
    }

    func refreshIfStale() {
        if rates.isFallback || Date().timeIntervalSince(rates.updatedAt ?? .distantPast) > refreshInterval {
            refresh()
        }
    }

    func refresh() {
        guard !isFetching else { return }
        isFetching = true
        URLSession.shared.dataTask(with: endpoint) { [weak self] data, _, _ in
            let fetched = data.flatMap(Self.decode)
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetching = false
                guard let fetched else { return }
                self.rates = fetched
                if let data = try? JSONEncoder().encode(fetched) {
                    try? data.write(to: Self.cacheURL, options: .atomic)
                }
            }
        }.resume()
    }

    /// "汇率更新于 10月4日 08:02", for the footer and settings.
    var statusText: String {
        if rates.isFallback { return "汇率：内置参考值" }
        guard let date = rates.updatedAt else { return "汇率已更新" }
        let f = DateFormatter()
        f.dateFormat = "M月d日 HH:mm"
        return "汇率更新于 \(f.string(from: date))"
    }

    private struct Response: Decodable {
        let result: String
        let base_code: String
        let time_last_update_unix: TimeInterval
        let rates: [String: Decimal]
    }

    private static func decode(_ data: Data) -> ExchangeRates? {
        guard let r = try? JSONDecoder().decode(Response.self, from: data), r.result == "success", !r.rates.isEmpty else {
            return nil
        }
        return ExchangeRates(
            base: r.base_code,
            rates: r.rates,
            updatedAt: Date(timeIntervalSince1970: r.time_last_update_unix)
        )
    }
}

enum AppPaths {
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Numo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Where notes lived before Numo became document-based.
    static var legacyNotes: URL { supportDirectory.appendingPathComponent("notes.txt") }

    static var defaultSaveDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Numo", isDirectory: true)
    }
}
