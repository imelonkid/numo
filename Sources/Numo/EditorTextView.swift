import AppKit
import NumoCore

/// The notepad. Text lives on the left; each line's result is drawn right-aligned in a column on the right.
final class EditorTextView: NSTextView {
    var results: [LineResult] = [] {
        didSet {
            if let line = selectedResultLine, !(results.indices.contains(line) && results[line].quantity != nil) {
                selectedResultLine = nil
            }
            overlay.needsDisplay = true
        }
    }
    /// Copies the result of a line to the pasteboard; returns the copied text.
    var onCopyResult: ((Int) -> String?)?

    /// A result picked in the result column (click). ⌘C copies it instead of the text selection.
    private(set) var selectedResultLine: Int? {
        didSet {
            if oldValue != selectedResultLine {
                EventLog.log("editor.selectedResultLine \(oldValue.map { String($0 + 1) } ?? "none") -> \(selectedResultLine.map { String($0 + 1) } ?? "none")")
                overlay.needsDisplay = true
            }
        }
    }

    private var resultHitRects: [(rect: NSRect, line: Int)] = []
    private var copiedLine: Int?
    private var copiedResetWork: DispatchWorkItem?

    var resultColumnWidth: CGFloat { max(150, bounds.width * 0.36) }

    /// Results are drawn in a transparent subview: NSTextView clips its own drawing to the text, so
    /// anything drawn after `super.draw` in the result column never shows up.
    private let overlay = ResultsOverlay()

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        overlay.owner = self
        overlay.frame = bounds
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateContainerWidth()
        overlay.needsDisplay = true
    }

    func updateContainerWidth() {
        guard let tc = textContainer else { return }
        let width = max(80, bounds.width - resultColumnWidth - textContainerInset.width)
        if tc.size.width != width {
            tc.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    override func didChangeText() {
        super.didChangeText()
        selectedResultLine = nil
        overlay.needsDisplay = true
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        needsDisplay = true  // current-line highlight
    }

    /// Typed "*" and "-" show as "×" and "−". Pasted text is left alone; the lexer accepts both.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        if let s = string as? String {
            switch s {
            case "*": return super.insertText("×", replacementRange: replacementRange)
            case "-": return super.insertText("−", replacementRange: replacementRange)
            default: break
            }
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    // MARK: Geometry

    private struct Row {
        let line: Int
        /// The fixed-height row of the line's first fragment, in view coordinates.
        let rect: NSRect
        /// From the first fragment to the last one (wrapped lines), in view coordinates.
        let fullRect: NSRect
    }

    /// One row per logical line, matching the controller's line ranges.
    private func rows() -> [Row] {
        guard let lm = layoutManager else { return [] }
        let text = string as NSString
        let origin = textContainerOrigin
        var rows: [Row] = []

        func makeRow(first: NSRect, last: NSRect) -> Row {
            let top = first.maxY - Theme.lineHeight  // skips paragraphSpacingBefore
            let rect = NSRect(x: 0, y: top + origin.y, width: bounds.width, height: Theme.lineHeight)
            let full = NSRect(x: 0, y: top + origin.y, width: bounds.width, height: last.maxY - top)
            return Row(line: rows.count, rect: rect, fullRect: full)
        }

        var location = 0
        while location < text.length {
            let lineRange = text.lineRange(for: NSRange(location: location, length: 0))
            let glyphs = lm.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let first = lm.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let last = glyphs.length > 0 ? lm.lineFragmentRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil) : first
            rows.append(makeRow(first: first, last: last))
            location = NSMaxRange(lineRange)
        }
        if text.length == 0 || isNewline(text.character(at: text.length - 1)) {
            let extra = lm.extraLineFragmentRect
            rows.append(makeRow(first: extra, last: extra))
        }
        return rows
    }

    private func isNewline(_ c: unichar) -> Bool { c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029 }

    /// Index of the logical line holding the caret, or nil while a range is selected.
    private func currentLineIndex() -> Int? {
        let selection = selectedRange()
        guard selection.length == 0 else { return nil }
        let text = string as NSString
        var line = 0
        var location = 0
        while location < text.length {
            let r = text.lineRange(for: NSRange(location: location, length: 0))
            let endsWithNewline = isNewline(text.character(at: NSMaxRange(r) - 1))
            if selection.location < NSMaxRange(r) || (!endsWithNewline && selection.location == NSMaxRange(r)) { break }
            line += 1
            location = NSMaxRange(r)
        }
        return line
    }

    // MARK: Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard Settings.shared.highlightCurrentLine, window?.isKeyWindow == true, let current = currentLineIndex(),
              let row = rows().first(where: { $0.line == current }) else { return }
        let inset = textContainerInset.width - 12
        let r = NSRect(x: inset, y: row.fullRect.minY, width: bounds.width - inset * 2, height: row.fullRect.height)
        Theme.currentLine.setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
    }

    fileprivate func drawResults(in dirtyRect: NSRect) {
        resultHitRects.removeAll()

        let left = textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0)
        let right = bounds.width - left
        let columnWidth = resultColumnWidth - 16
        let decimals = Settings.shared.decimalPlaces


        for row in rows() {
            guard row.line < results.count else { break }
            let result = results[row.line]

            if result.isTotal {
                let y = (row.rect.minY - Theme.totalSpacing / 2).rounded()
                let line = NSRect(x: left, y: y, width: right - left, height: 1)
                if line.intersects(dirtyRect) {
                    Theme.divider.setFill()
                    line.fill()
                }
            }

            let isCopied = copiedLine == row.line
            let text: String
            if isCopied {
                text = "已拷贝"
            } else if let q = result.quantity {
                text = QuantityFormatter.display(q, decimals: decimals)
            } else {
                continue
            }

            let rect = NSRect(x: right - columnWidth, y: row.rect.minY, width: columnWidth, height: row.rect.height)
            let isSelected = selectedResultLine == row.line && !isCopied
            let attributed = NSAttributedString(string: text, attributes: [
                .font: result.isTotal && !isCopied ? Theme.totalFont : Theme.resultFont,
                .foregroundColor: isCopied ? Theme.syntax : (result.isTotal ? Theme.text : Theme.result),
                .paragraphStyle: Theme.paragraphStyle(alignment: .right),
                .baselineOffset: Theme.baselineOffset,
            ])
            // Hit area hugs the visible text so clicks in empty space still place the caret.
            let textWidth = min(columnWidth, attributed.size().width)
            resultHitRects.append((NSRect(x: right - textWidth - 6, y: rect.minY, width: textWidth + 12, height: rect.height), row.line))

            if isSelected {
                let h = Theme.resultFont.ascender - Theme.resultFont.descender + 8
                let highlight = NSRect(x: right - textWidth - 6, y: rect.midY - h / 2, width: textWidth + 12, height: h)
                let focused = window?.isKeyWindow == true && window?.firstResponder === self
                (focused ? NSColor.selectedTextBackgroundColor : NSColor.unemphasizedSelectedTextBackgroundColor).setFill()
                NSBezierPath(roundedRect: highlight, xRadius: 5, yRadius: 5).fill()
            }

            if rect.intersects(dirtyRect) {
                attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            }
        }
    }

    // MARK: Selecting and copying results

    private func resultLine(at point: NSPoint) -> Int? {
        resultHitRects.first(where: { $0.rect.contains(point) && results.indices.contains($0.line) && results[$0.line].quantity != nil })?.line
    }

    /// NSTextView lets clicks outside its text container fall through to the clip view, and the
    /// result column lies outside it. Claim clicks that land on a result.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let superview, let line = resultLine(at: convert(point, from: superview)) {
            EventLog.log("editor.hitTest claims click on result line \(line + 1)")
            return self
        }
        return super.hitTest(point)
    }

    /// A click on a result in a background window selects it right away.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        if let event, resultLine(at: convert(event.locationInWindow, from: nil)) != nil {
            EventLog.log("editor.acceptsFirstMouse -> true (result)")
            return true
        }
        return super.acceptsFirstMouse(for: event)
    }

    /// Clicking a result selects it (like selecting text); ⌘C or 右键 → 拷贝 copies it.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let line = resultLine(at: p)
        EventLog.log("editor.mouseDown point=\(p) resultLine=\(line.map { String($0 + 1) } ?? "none") resultRects=\(resultHitRects.map { "\($0.line + 1):\(Int($0.rect.minX))-\(Int($0.rect.maxX))x\(Int($0.rect.minY))-\(Int($0.rect.maxY))" }.joined(separator: " "))")
        if let line {
            selectedResultLine = line
            window?.makeFirstResponder(self)
            return
        }
        selectedResultLine = nil
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = convert(event.locationInWindow, from: nil)
        guard let line = resultLine(at: p) else {
            selectedResultLine = nil
            return super.menu(for: event)
        }
        selectedResultLine = line
        let menu = NSMenu()
        menu.addItem(withTitle: "拷贝", action: #selector(copy(_:)), keyEquivalent: "").target = self
        return menu
    }

    override func copy(_ sender: Any?) {
        if let line = selectedResultLine, let text = onCopyResult?(line) {
            EventLog.log("editor.copy result line \(line + 1): \(text)")
            return
        }
        EventLog.log("editor.copy text selection")
        super.copy(sender)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)), selectedResultLine != nil { return true }
        return super.validateUserInterfaceItem(item)
    }

    override func keyDown(with event: NSEvent) {
        if selectedResultLine != nil {
            selectedResultLine = nil
            if event.keyCode == 53 { return }  // Esc only clears the result selection
        }
        super.keyDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        overlay.needsDisplay = true  // selection turns gray
        return super.resignFirstResponder()
    }

    override func becomeFirstResponder() -> Bool {
        overlay.needsDisplay = true
        return super.becomeFirstResponder()
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if resultLine(at: p) != nil {
            NSCursor.arrow.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    func flashCopied(_ line: Int) {
        copiedLine = line
        overlay.needsDisplay = true
        copiedResetWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.copiedLine = nil
            self?.overlay.needsDisplay = true
        }
        copiedResetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }
}

private final class ResultsOverlay: NSView {
    weak var owner: EditorTextView?

    override var isFlipped: Bool { true }
    /// Clicks go to the text view, which handles both editing and click-to-copy.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        owner?.drawResults(in: dirtyRect)
    }
}
