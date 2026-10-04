import AppKit

/// Debug log of mouse / keyboard handling, written to ~/Library/Logs/Numo/events.log.
/// Off by default; enable with `defaults write com.melonkid.numo eventLog -bool YES` (restart Numo).
enum EventLog {
    static let isEnabled = UserDefaults.standard.bool(forKey: "eventLog")

    static let fileURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Numo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("events.log")
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static var handle: FileHandle? = {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        let h = try? FileHandle(forWritingTo: fileURL)
        h?.seekToEndOfFile()
        return h
    }()

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let line = "\(formatter.string(from: Date())) \(message())\n"
        handle?.write(Data(line.utf8))
    }

    private static var monitor: Any?

    /// Window-level view of every click and key press: where it landed and which view got it.
    static func installMonitor() {
        guard isEnabled, monitor == nil else { return }
        log("---- Numo started, pid \(ProcessInfo.processInfo.processIdentifier)")
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { event in
            switch event.type {
            case .keyDown:
                log("keyDown keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "") mods=\(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue) firstResponder=\(describe(event.window?.firstResponder))")
            default:
                let target = event.window?.contentView?.superview?.hitTest(event.locationInWindow)
                log("\(event.type == .leftMouseDown ? "leftMouseDown" : "rightMouseDown") window=\(event.locationInWindow) keyWindow=\(event.window?.isKeyWindow ?? false) hitView=\(describe(target))")
            }
            return event
        }
    }

    static func describe(_ object: AnyObject?) -> String {
        object.map { String(describing: type(of: $0)) } ?? "nil"
    }
}
