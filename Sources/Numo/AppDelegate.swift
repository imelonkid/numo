import AppKit
import NumoCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: HotKey?
    private lazy var settingsWindow = SettingsWindowController()
    private let env = ProcessInfo.processInfo.environment

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set before the document controller looks for the "Open Recent" menu.
        NSApp.mainMenu = makeMainMenu()
        NSApp.appearance = Settings.shared.appearance.nsAppearance
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if env["NUMO_SNAPSHOT"] == nil { NSApp.activate(ignoringOtherApps: true) }

        // ⌥Space shows / hides Numo from anywhere.
        hotKey = HotKey { [weak self] in self?.toggleVisibility() }

        RateService.shared.start()
        EventLog.installMonitor()
        runSnapshotIfRequested()
    }

    /// Called at launch when no documents were restored, and on reopen.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if env["NUMO_SNAPSHOT"] != nil { return false }
        if let legacy = migrateLegacyNotes() {
            open(legacy)
            return false
        }
        // First launch: an untitled note with a short sample (nothing is written to disk).
        if !Settings.shared.welcomeShown {
            Settings.shared.welcomeShown = true
            NumoDocument.pendingInitialText = Guide.welcome
            return true
        }
        if Settings.shared.reopenLastDocument,
           let recent = NSDocumentController.shared.recentDocumentURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            open(recent)
            return false
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func open(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if error != nil { NSDocumentController.shared.newDocument(nil) }
        }
    }

    // MARK: Window toggling

    private func toggleVisibility() {
        if NSApp.isActive, NSApp.keyWindow?.windowController?.document != nil {
            NSApp.hide(nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let documentWindows = NSDocumentController.shared.documents.flatMap { $0.windowControllers.compactMap(\.window) }
        if let window = documentWindows.first {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSDocumentController.shared.newDocument(nil)
        }
    }

    @objc private func showSettings(_ sender: Any?) {
        settingsWindow.show()
    }

    // MARK: Migration

    /// Notes used to live in Application Support/Numo/notes.txt. Move them next to the user's documents once.
    private func migrateLegacyNotes() -> URL? {
        let fm = FileManager.default
        let legacy = AppPaths.legacyNotes
        guard fm.fileExists(atPath: legacy.path) else { return nil }
        let directory = Settings.shared.saveDirectory
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var target = directory.appendingPathComponent("Numo 笔记.txt")
        var n = 2
        while fm.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent("Numo 笔记 \(n).txt")
            n += 1
        }
        do {
            try fm.moveItem(at: legacy, to: target)
            return target
        } catch {
            return nil
        }
    }

    // MARK: Syntax guide

    /// Help → 语法速查: a built-in, never-saved document in a new tab (or the existing one).
    @objc private func showGuide(_ sender: Any?) {
        let controller = NSDocumentController.shared
        if let existing = controller.documents.first(where: { ($0 as? NumoDocument)?.isGuide == true }) {
            existing.showWindows()
            existing.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
            return
        }
        let guide = NumoDocument.makeGuide()
        controller.addDocument(guide)
        guide.makeWindowControllers()
        guide.showWindows()
    }

    /// The "+" button in the tab bar.
    @objc func newWindowForTab(_ sender: Any?) {
        NSDocumentController.shared.newDocument(sender)
    }

    // MARK: Dev snapshot hook

    /// NUMO_SNAPSHOT=out.png renders a window to a PNG and quits. NUMO_DOC=file.txt picks the document
    /// (opened without touching Recents; add NUMO_SNAPSHOT_GUIDE=1 to open the guide as a second tab), NUMO_SNAPSHOT_SETTINGS=1 renders settings (=2 for the 通用 tab),
    /// NUMO_DARK=1 forces dark mode, NUMO_SNAPSHOT_HEIGHT sets the window height.
    /// Launch with `-ApplePersistenceIgnoreState YES` so the user's restored windows stay out of it.
    private func runSnapshotIfRequested() {
        guard let path = env["NUMO_SNAPSHOT"] else { return }

        var target: NSWindow?
        if let tab = env["NUMO_SNAPSHOT_SETTINGS"] {
            settingsWindow.show(tab: tab == "2" ? 1 : 0)
            target = settingsWindow.window
        } else if env["NUMO_DOC"] == "untitled" {
            NSDocumentController.shared.newDocument(nil)
            target = NSDocumentController.shared.documents.last?.windowControllers.first?.window
        } else if let docPath = env["NUMO_DOC"],
                  let doc = try? NSDocumentController.shared.makeDocument(
                      withContentsOf: URL(fileURLWithPath: docPath), ofType: "public.plain-text") {
            NSDocumentController.shared.addDocument(doc)
            doc.makeWindowControllers()
            doc.showWindows()
            target = doc.windowControllers.first?.window
            if env["NUMO_SNAPSHOT_GUIDE"] != nil {
                showGuide(nil)
                target = NSDocumentController.shared.documents.last?.windowControllers.first?.window
            }
            if let h = env["NUMO_SNAPSHOT_HEIGHT"].flatMap(Double.init) {
                target?.setContentSize(NSSize(width: 680, height: h))
            }
        }
        // After the editor applied the user's appearance setting.
        NSApp.appearance = NSAppearance(named: env["NUMO_DARK"] != nil ? .darkAqua : .aqua)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if let v = target?.contentView?.superview,
               let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            exit(0)
        }
    }

    // MARK: Menu

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu(title: "Numo")
        appMenu.addItem(withTitle: "关于 Numo", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "设置…", action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Numo", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
            .keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Numo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addSubmenu(appMenu)

        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(withTitle: "新建", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "打开…", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        // NSDocumentController fills the menu that contains clearRecentDocuments:.
        let recentMenu = NSMenu(title: "打开最近使用")
        recentMenu.addItem(withTitle: "清除菜单", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        main.addSubmenu(recentMenu, to: fileMenu)
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(withTitle: "保存…", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "另存为…", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "s")
            .keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "重新命名…", action: #selector(NSDocument.rename(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: "移到…", action: #selector(NSDocument.move(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: "复原到上次保存", action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")
        main.addSubmenu(fileMenu)

        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
            .keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "拷贝当前行结果", action: #selector(EditorViewController.copyCurrentResult(_:)), keyEquivalent: "c")
            .keyEquivalentModifierMask = [.command, .shift]
        main.addSubmenu(editMenu)

        let rateMenu = NSMenu(title: "汇率")
        rateMenu.addItem(withTitle: "立即更新汇率", action: #selector(EditorViewController.refreshRates(_:)), keyEquivalent: "r")
        main.addSubmenu(rateMenu)

        let viewMenu = NSMenu(title: "显示")
        viewMenu.addItem(withTitle: "显示标签页栏", action: #selector(NSWindow.toggleTabBar(_:)), keyEquivalent: "")
        viewMenu.addItem(withTitle: "显示所有标签页", action: #selector(NSWindow.toggleTabOverview(_:)), keyEquivalent: "\\")
            .keyEquivalentModifierMask = [.command, .shift]
        main.addSubmenu(viewMenu)

        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        main.addSubmenu(windowMenu)
        NSApp.windowsMenu = windowMenu

        let helpMenu = NSMenu(title: "帮助")
        helpMenu.addItem(withTitle: Guide.title, action: #selector(showGuide(_:)), keyEquivalent: "?").target = self
        main.addSubmenu(helpMenu)
        NSApp.helpMenu = helpMenu

        return main
    }
}

private extension NSMenu {
    func addSubmenu(_ submenu: NSMenu, to parent: NSMenu? = nil) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        (parent ?? self).addItem(item)
    }
}


