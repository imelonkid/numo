import AppKit
import Combine
import NumoCore

final class EditorViewController: NSViewController, NSTextViewDelegate {
    private weak var document: NumoDocument?
    private let rateService = RateService.shared
    private var textView: EditorTextView!
    private var lineLabel: NSTextField!
    private var resultLabel: NSTextField!
    private var tint: FillView!
    private var observers: Set<AnyCancellable> = []
    private var lineRanges: [NSRange] = []

    init(document: NumoDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .followsWindowActiveState

        // Warm tint over the frosted glass.
        tint = FillView(color: { Theme.tint })
        tint.translatesAutoresizingMaskIntoConstraints = false

        // TextKit 1 stack: we need NSLayoutManager to align results with line fragments.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layout.addTextContainer(container)

        textView = EditorTextView(frame: .zero, textContainer: container)
        textView.delegate = self
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: Theme.horizontalInset, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.onCopyResult = { [weak self] line in self?.copyResult(line: line) }

        let scroll = EditorScrollView()
        scroll.drawsBackground = false
        scroll.verticalScroller = SlimScroller()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true  // hidden only when everything fits
        scroll.documentView = textView
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let footer = makeFooter()

        background.addSubview(tint)
        background.addSubview(scroll)
        background.addSubview(footer)
        NSLayoutConstraint.activate([
            tint.topAnchor.constraint(equalTo: background.topAnchor),
            tint.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: background.safeAreaLayoutGuide.topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        view = background

        textView.string = document?.text ?? ""
        document?.onTextLoaded = { [weak self] in
            guard let self, let text = self.document?.text, text != self.textView.string else { return }
            self.textView.string = text
            self.recalculate()
        }
        applySettings()

        // objectWillChange fires before the new value is stored, so apply on the next turn.
        Settings.shared.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.applySettings() } }
            .store(in: &observers)
        rateService.$rates.dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.recalculate() } }
            .store(in: &observers)

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.textView.needsDisplay = true }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.textView.needsDisplay = true }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
        textView.updateContainerWidth()
    }

    // MARK: Settings

    private func applySettings() {
        NSApp.appearance = Settings.shared.appearance.nsAppearance
        textView.font = Theme.font
        textView.defaultParagraphStyle = Theme.paragraphStyle()
        textView.typingAttributes = baseAttributes(Theme.paragraphStyle())
        tint.needsDisplay = true
        recalculate()
        textView.needsDisplay = true
        textView.subviews.forEach { $0.needsDisplay = true }  // results overlay
    }

    // MARK: Footer

    private func makeFooter() -> NSView {
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false

        let separator = FillView(color: { Theme.divider })
        separator.translatesAutoresizingMaskIntoConstraints = false

        // Status bar: current line number on the left, that line's result on the right.
        let left = label("", color: Theme.syntax)
        lineLabel = left
        let right = NSTextField(labelWithString: "")
        right.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        right.textColor = Theme.syntax
        right.lineBreakMode = .byTruncatingHead
        right.alignment = .right
        right.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        resultLabel = right

        for v in [separator, left, right] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(v)
        }
        let inset = Theme.horizontalInset + 5
        NSLayoutConstraint.activate([
            footer.heightAnchor.constraint(equalToConstant: 40),
            separator.topAnchor.constraint(equalTo: footer.topAnchor),
            separator.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),
            left.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: inset),
            left.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -inset),
            right.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            right.leadingAnchor.constraint(greaterThanOrEqualTo: left.trailingAnchor, constant: 16),
        ])
        return footer
    }

    private func label(_ text: String, color: NSColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12)
        l.textColor = color
        l.lineBreakMode = .byTruncatingTail
        return l
    }

    // MARK: Evaluation

    func textDidChange(_ notification: Notification) {
        // The edit itself is tracked by the document's undo manager (change count, autosave).
        document?.updateText(textView.string)
        recalculate()
    }

    private func recalculate() {
        let text = textView.string as NSString
        lineRanges = Self.lineRanges(of: text)
        let lines = lineRanges.map { text.substring(with: $0) }
        let results = Document.evaluate(lines, rates: rateService.rates)
        highlight(lines, results: results)
        textView.results = results
        updateFooter()
    }

    /// Logical lines without terminators. A trailing newline yields a final empty line.
    private static func lineRanges(of text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var location = 0
        while location < text.length {
            var end = 0, contentsEnd = 0
            text.getLineStart(nil, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            ranges.append(NSRange(location: location, length: contentsEnd - location))
            location = end
        }
        if text.length == 0 || [0x0A, 0x0D, 0x2028, 0x2029].contains(text.character(at: text.length - 1)) {
            ranges.append(NSRange(location: text.length, length: 0))
        }
        return ranges
    }

    private func baseAttributes(_ paragraph: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [.font: Theme.font, .foregroundColor: Theme.text, .paragraphStyle: paragraph, .baselineOffset: Theme.baselineOffset]
    }

    private func highlight(_ lines: [String], results: [LineResult]) {
        guard let storage = textView.textStorage else { return }
        let normal = Theme.paragraphStyle()
        let total = Theme.paragraphStyle(spacingBefore: Theme.totalSpacing)

        storage.beginEditing()
        storage.setAttributes(baseAttributes(normal), range: NSRange(location: 0, length: storage.length))
        for (i, (lineRange, line)) in zip(lineRanges, lines).enumerated() {
            let result = i < results.count ? results[i] : .empty
            func apply(_ r: Range<Int>, _ attrs: [NSAttributedString.Key: Any]) {
                let range = NSRange(location: lineRange.location + r.lowerBound, length: r.count)
                if NSMaxRange(range) <= storage.length { storage.addAttributes(attrs, range: range) }
            }

            if result.isTotal {
                let paragraphRange = (storage.string as NSString).paragraphRange(for: lineRange)
                storage.addAttribute(.paragraphStyle, value: total, range: paragraphRange)
            }
            for h in Highlighter.highlights(for: line) {
                switch h.kind {
                case .number, .constant:
                    break
                case .variable:
                    apply(h.range, [.font: Theme.variableFont])
                case .comment:
                    apply(h.range, [.foregroundColor: Theme.comment])
                case .op, .unit, .keyword, .function, .label:
                    apply(h.range, [.foregroundColor: Theme.syntax])
                }
            }
            // Plain-word labels ("房租 3000¥") and total lines read as quiet text.
            if let label = result.label {
                apply(label, [.foregroundColor: Theme.syntax, .font: Theme.font])
            }
            if result.isTotal {
                apply(0..<lineRange.length, [.foregroundColor: Theme.syntax, .font: Theme.font])
            }
        }
        storage.endEditing()
    }

    /// Line number of the caret (start of the selection) and that line's result.
    private func updateFooter() {
        let caret = textView.selectedRange().location
        let line = lineRanges.lastIndex(where: { $0.location <= caret }) ?? 0
        lineLabel.stringValue = "第 \(line + 1) 行"
        let result = line < textView.results.count ? textView.results[line].quantity : nil
        resultLabel.stringValue = result.map { QuantityFormatter.display($0, decimals: Settings.shared.decimalPlaces) } ?? ""
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        updateFooter()
    }

    // MARK: Copy

    @discardableResult
    private func copyResult(line: Int) -> String? {
        guard textView.results.indices.contains(line), let q = textView.results[line].quantity else { return nil }
        let text = QuantityFormatter.copyText(q, decimals: Settings.shared.decimalPlaces)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return text
    }

    @objc func copyCurrentResult(_ sender: Any?) {
        let caret = textView.selectedRange().location
        guard let line = lineRanges.lastIndex(where: { $0.location <= caret }) else { return }
        if copyResult(line: line) != nil {
            textView.flashCopied(line)
        } else {
            NSSound.beep()
        }
    }

    @objc func refreshRates(_ sender: Any?) {
        rateService.refresh()
    }
}

/// A view that fills itself with a (dynamic) color, re-resolved on appearance changes.
final class FillView: NSView {
    /// Read on every draw so settings changes (e.g. frosted glass on/off) take effect.
    private let color: () -> NSColor
    private let cornerRadius: CGFloat

    init(color: @escaping () -> NSColor, cornerRadius: CGFloat = 0) {
        self.color = color
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        color().setFill()
        // Fill our own bounds, not dirtyRect: AppKit may pass a rect larger than the view.
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
