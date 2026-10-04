import AppKit

/// Keeps dev snapshot runs (NUMO_SNAPSHOT) out of the user's Open Recent list.
final class NumoDocumentController: NSDocumentController {
    override func noteNewRecentDocumentURL(_ url: URL) {
        if ProcessInfo.processInfo.environment["NUMO_SNAPSHOT"] != nil { return }
        super.noteNewRecentDocumentURL(url)
    }
}
