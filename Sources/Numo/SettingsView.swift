import AppKit
import SwiftUI

// MARK: - 外观

struct AppearanceSettingsView: View {
    @ObservedObject var settings = Settings.shared

    var body: some View {
        Form {
            Section("主题") {
                Picker("外观", selection: $settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("毛玻璃背景", isOn: $settings.frostedGlass)
            }

            Section("文字") {
                LabeledContent("字号") {
                    HStack(spacing: 10) {
                        Slider(value: $settings.fontSize, in: Settings.fontSizeRange, step: 1)
                            .frame(width: 160)
                        Text("\(Int(settings.fontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Picker("行距", selection: $settings.lineSpacing) {
                    ForEach(LineSpacing.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("结果") {
                LabeledContent("结果颜色") {
                    HStack(spacing: 10) {
                        ForEach(ResultColor.allCases) { choice in
                            Swatch(color: Color(nsColor: choice.color), selected: settings.resultColor == choice)
                                .help(choice.title)
                                .onTapGesture { settings.resultColor = choice }
                        }
                    }
                }
                LabeledContent("小数位数") {
                    Stepper(value: $settings.decimalPlaces, in: Settings.decimalPlacesRange) {
                        Text("最多 \(settings.decimalPlaces) 位")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("高亮当前行", isOn: $settings.highlightCurrentLine)
            }

            HStack {
                Spacer()
                Button("恢复默认外观") { settings.resetAppearance() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Swatch: View {
    let color: Color
    let selected: Bool

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 18, height: 18)
            .padding(3)
            .overlay(Circle().strokeBorder(selected ? Color.primary.opacity(0.5) : .clear, lineWidth: 1.5))
            .contentShape(Circle())
    }
}

// MARK: - 通用

struct GeneralSettingsView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var rates = RateService.shared

    var body: some View {
        Form {
            Section("文稿") {
                LabeledContent("默认保存位置") {
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(for: .folder))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(displayPath(settings.saveDirectory))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Spacer()
                    Button("在 Finder 中显示") { revealSaveDirectory() }
                    Button("选择…") { chooseSaveDirectory() }
                }
                Toggle("启动时打开上次的文稿", isOn: $settings.reopenLastDocument)
            }

            Section("汇率") {
                LabeledContent("状态") {
                    Text(rates.statusText).foregroundStyle(.secondary)
                }
                HStack {
                    Text("每 6 小时自动更新，离线时使用缓存")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("立即更新") { rates.refresh() }
                }
            }

            Section("快捷键") {
                LabeledContent("呼出 / 隐藏 Numo") {
                    Text("⌥ Space").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        panel.message = "选择新文稿的默认保存位置"
        panel.directoryURL = settings.saveDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectory = url
        }
    }

    private func revealSaveDirectory() {
        let dir = settings.saveDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}

// MARK: - Window

/// Toolbar-style tabs, like the system Settings windows. The window resizes to fit each tab.
final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow(to: tabViewItem, animate: true)
    }

    func fitWindow(to item: NSTabViewItem?, animate: Bool) {
        guard let window = view.window, let content = item?.viewController?.view else { return }
        let size = content.fittingSize
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        let origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(NSRect(origin: origin, size: frame.size), display: true, animate: animate && window.isVisible)
    }
}

final class SettingsWindowController: NSWindowController {
    private var tabs: SettingsTabViewController!

    convenience init() {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar

        // The selected tab's title becomes the window title.
        let appearanceController = NSHostingController(rootView: AppearanceSettingsView())
        appearanceController.title = "外观"
        let generalController = NSHostingController(rootView: GeneralSettingsView())
        generalController.title = "通用"

        let appearance = NSTabViewItem(viewController: appearanceController)
        appearance.label = "外观"
        appearance.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "外观")
        let general = NSTabViewItem(viewController: generalController)
        general.label = "通用"
        general.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "通用")
        tabs.addTabViewItem(appearance)
        tabs.addTabViewItem(general)

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        self.init(window: window)
        self.tabs = tabs
    }

    /// - Parameter tab: 0 = 外观, 1 = 通用.
    func show(tab: Int? = nil) {
        if let tab { tabs.selectedTabViewItemIndex = tab }
        tabs.fitWindow(to: tabs.tabViewItems[tabs.selectedTabViewItemIndex], animate: false)
        if window?.isVisible != true { window?.center() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
