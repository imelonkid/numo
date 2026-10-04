import AppKit

/// Scroll view whose scroller stays visible while the content is scrollable, instead of the
/// system overlay scroller that fades out when idle.
final class EditorScrollView: NSScrollView {
    override var scrollerStyle: NSScroller.Style {
        get { .legacy }
        // The system pushes its preferred style on preference changes; keep ours.
        set { super.scrollerStyle = .legacy }
    }
}

/// A thin scroller: transparent track, rounded translucent knob.
final class SlimScroller: NSScroller {
    private static let width: CGFloat = 11

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        width
    }

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Transparent track so the frosted background shows through.
    }

    override func drawKnob() {
        let knob = rect(for: .knob).insetBy(dx: 3, dy: 3)
        guard knob.height > 0 else { return }
        Theme.scrollerKnob.setFill()
        NSBezierPath(roundedRect: knob, xRadius: knob.width / 2, yRadius: knob.width / 2).fill()
    }
}
