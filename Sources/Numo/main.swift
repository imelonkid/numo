import AppKit

let app = NSApplication.shared
// The first document controller created becomes NSDocumentController.shared.
_ = NumoDocumentController()
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
