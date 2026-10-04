import AppKit
import Combine
import NumoCore

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum LineSpacing: String, CaseIterable, Identifiable {
    case compact, standard, relaxed
    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "紧凑"
        case .standard: return "标准"
        case .relaxed: return "宽松"
        }
    }

    /// Line height as a multiple of the font size.
    var multiplier: CGFloat {
        switch self {
        case .compact: return 1.6
        case .standard: return 2.0
        case .relaxed: return 2.4
        }
    }
}

enum ResultColor: String, CaseIterable, Identifiable {
    case slate, accent, green, orange, text
    var id: String { rawValue }

    var title: String {
        switch self {
        case .slate: return "雾蓝"
        case .accent: return "系统强调色"
        case .green: return "青绿"
        case .orange: return "暖橙"
        case .text: return "正文色"
        }
    }

    var color: NSColor {
        switch self {
        case .slate:
            return Theme.dynamic(light: NSColor(srgbRed: 0.20, green: 0.31, blue: 0.56, alpha: 1),
                                 dark: NSColor(srgbRed: 0.58, green: 0.66, blue: 0.86, alpha: 1))
        case .accent:
            return .controlAccentColor
        case .green:
            return Theme.dynamic(light: NSColor(srgbRed: 0.10, green: 0.46, blue: 0.38, alpha: 1),
                                 dark: NSColor(srgbRed: 0.46, green: 0.78, blue: 0.68, alpha: 1))
        case .orange:
            return Theme.dynamic(light: NSColor(srgbRed: 0.68, green: 0.36, blue: 0.10, alpha: 1),
                                 dark: NSColor(srgbRed: 0.93, green: 0.66, blue: 0.42, alpha: 1))
        case .text:
            return .labelColor
        }
    }
}

/// User preferences, persisted in UserDefaults. Observe `objectWillChange` to re-apply.
final class Settings: ObservableObject {
    static let shared = Settings()

    static let fontSizeRange: ClosedRange<Double> = 13...24
    static let decimalPlacesRange: ClosedRange<Int> = 0...10

    private enum Key {
        static let appearance = "appearance"
        static let fontSize = "fontSize"
        static let lineSpacing = "lineSpacing"
        static let resultColor = "resultColor"
        static let frostedGlass = "frostedGlass"
        static let highlightCurrentLine = "highlightCurrentLine"
        static let decimalPlaces = "decimalPlaces"
        static let saveDirectory = "saveDirectory"
        static let reopenLastDocument = "reopenLastDocument"
        static let welcomeShown = "welcomeShown"
    }

    private let defaults = UserDefaults.standard

    @Published var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }
    @Published var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: Key.fontSize) }
    }
    @Published var lineSpacing: LineSpacing {
        didSet { defaults.set(lineSpacing.rawValue, forKey: Key.lineSpacing) }
    }
    @Published var resultColor: ResultColor {
        didSet { defaults.set(resultColor.rawValue, forKey: Key.resultColor) }
    }
    @Published var frostedGlass: Bool {
        didSet { defaults.set(frostedGlass, forKey: Key.frostedGlass) }
    }
    @Published var highlightCurrentLine: Bool {
        didSet { defaults.set(highlightCurrentLine, forKey: Key.highlightCurrentLine) }
    }
    /// Maximum decimal places for plain numbers and percentages; currencies keep their own (e.g. 2).
    @Published var decimalPlaces: Int {
        didSet { defaults.set(decimalPlaces, forKey: Key.decimalPlaces) }
    }

    // General
    /// Default folder for the save panel.
    @Published var saveDirectory: URL {
        didSet { defaults.set(saveDirectory.path, forKey: Key.saveDirectory) }
    }
    @Published var reopenLastDocument: Bool {
        didSet { defaults.set(reopenLastDocument, forKey: Key.reopenLastDocument) }
    }

    /// The short sample note is shown once, on the first launch.
    var welcomeShown: Bool {
        get { defaults.bool(forKey: Key.welcomeShown) }
        set { defaults.set(newValue, forKey: Key.welcomeShown) }
    }

    private init() {
        appearance = defaults.string(forKey: Key.appearance).flatMap(AppearanceMode.init) ?? .system
        let size = defaults.double(forKey: Key.fontSize)
        fontSize = Self.fontSizeRange.contains(size) ? size : 17
        lineSpacing = defaults.string(forKey: Key.lineSpacing).flatMap(LineSpacing.init) ?? .standard
        resultColor = defaults.string(forKey: Key.resultColor).flatMap(ResultColor.init) ?? .slate
        frostedGlass = defaults.object(forKey: Key.frostedGlass) as? Bool ?? true
        highlightCurrentLine = defaults.object(forKey: Key.highlightCurrentLine) as? Bool ?? true
        let places = defaults.object(forKey: Key.decimalPlaces) as? Int ?? QuantityFormatter.defaultDecimals
        decimalPlaces = Self.decimalPlacesRange.contains(places) ? places : QuantityFormatter.defaultDecimals
        saveDirectory = defaults.string(forKey: Key.saveDirectory).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? AppPaths.defaultSaveDirectory
        reopenLastDocument = defaults.object(forKey: Key.reopenLastDocument) as? Bool ?? true
    }

    /// Resets the appearance tab.
    func resetAppearance() {
        appearance = .system
        fontSize = 17
        lineSpacing = .standard
        resultColor = .slate
        frostedGlass = true
        highlightCurrentLine = true
        decimalPlaces = QuantityFormatter.defaultDecimals
    }
}
