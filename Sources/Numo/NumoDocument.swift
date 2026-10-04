import AppKit
import NumoCore
import UniformTypeIdentifiers

/// A Numo note: a plain-text file. NSDocument provides new/open/recent/save panels, autosave and versions.
@objc(NumoDocument)
final class NumoDocument: NSDocument {
    private(set) var text = ""
    /// Called after the contents were (re)loaded from disk, e.g. on "Revert To".
    var onTextLoaded: (() -> Void)?

    /// The built-in syntax reference: editable for trying things out, but never marked edited or saved.
    /// "另存为…" turns it into a normal note.
    private(set) var isGuide = false

    /// Content for the next untitled document (the short sample on first launch).
    static var pendingInitialText: String?

    override init() {
        super.init()
        if let initial = Self.pendingInitialText {
            text = initial
            Self.pendingInitialText = nil
        }
    }

    static func makeGuide() -> NumoDocument {
        let doc = NumoDocument()
        doc.isGuide = true
        doc.text = Guide.text
        return doc
    }

    override class var autosavesInPlace: Bool { true }

    override var fileURL: URL? {
        didSet { if fileURL != nil { isGuide = false } }
    }

    override var displayName: String! {
        get { isGuide ? Guide.title : super.displayName }
        set { super.displayName = newValue }
    }

    override var isDocumentEdited: Bool { isGuide ? false : super.isDocumentEdited }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        if !isGuide { super.updateChangeCount(change) }
    }

    override func makeWindowControllers() {
        let editor = EditorViewController(document: self)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        // All notes share one window as tabs.
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "NumoNote"
        // The guide is rebuilt from the app, never restored.
        window.isRestorable = !isGuide
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 360, height: 200)
        window.contentViewController = editor
        window.setContentSize(NSSize(width: 680, height: 640))
        window.center()

        let controller = NSWindowController(window: window)
        controller.shouldCascadeWindows = true
        // Only the first window gets the saved frame; later ones cascade from it.
        controller.windowFrameAutosaveName = "NumoWindow"
        addWindowController(controller)
    }

    /// New windows join the frontmost note window as a tab.
    override func showWindows() {
        if let window = windowControllers.first?.window, !window.isVisible,
           (window.tabbedWindows?.count ?? 1) <= 1,
           let host = Self.frontNoteWindow(excluding: window) {
            host.addTabbedWindow(window, ordered: .above)
        }
        super.showWindows()
    }

    static func frontNoteWindow(excluding window: NSWindow? = nil) -> NSWindow? {
        let candidates = NSApp.orderedWindows.filter {
            $0 !== window && $0.isVisible && $0.tabbingIdentifier == "NumoNote"
        }
        return candidates.first
    }

    /// Kept in sync by the editor on every edit, so autosave always writes the latest text.
    func updateText(_ newText: String) {
        text = newText
    }

    override func data(ofType typeName: String) throws -> Data {
        Data(text.utf8)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        // UTF-8 first, then GB18030 for older Chinese text files.
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        guard let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: gb18030) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        text = s
        onTextLoaded?()
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        let directory = Settings.shared.saveDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        savePanel.directoryURL = directory
        if isGuide { savePanel.nameFieldStringValue = Guide.title }
        savePanel.allowedContentTypes = [.plainText]
        return true
    }
}
