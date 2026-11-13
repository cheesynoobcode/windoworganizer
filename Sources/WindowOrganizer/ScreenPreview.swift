import AppKit
import WindowOrganizerCore

struct PreviewWindow: Equatable {
    var frame: Frame
    var title: String
    var bundleID: String
    var windowID: Int? = nil
    /// The card's app and its window title, for the accessibility label (the drawn title joins them).
    var app = ""
    var detail = ""
}

/// Interactive geometry only; this view never moves another app itself.
@MainActor
final class ScreenPreview: NSView {
    var screen: ScreenInfo?
    var windows: [PreviewWindow] = []
    var message = ""
    var editable = false
    var selectedID: Int?
    var changed: ((Int, Frame) -> Void)?
    /// A move (not a resize) ended with the pointer at this point, in screen coordinates.
    var dropped: ((Int, CGPoint) -> Void)?
    private var drag: (id: Int, start: CGPoint, frame: Frame, resize: Bool)?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { editable }
    func displayRect() -> CGRect {
        guard let screen, screen.frame.isValid else { return .zero }
        let area = bounds.insetBy(dx: 24, dy: 20)
        let scale = min(area.width / screen.frame.width, area.height / screen.frame.height)
        let size = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
        return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }
    func previewRect(_ frame: Frame) -> CGRect {
        guard let screen, screen.frame.isValid else { return .zero }
        let display = displayRect(), scale = display.width / screen.frame.width
        return CGRect(x: display.minX + (frame.x - screen.frame.x) * scale, y: display.minY + (frame.y - screen.frame.y) * scale, width: frame.width * scale, height: frame.height * scale)
    }
    func transformed(_ frame: Frame, delta: CGPoint, resize: Bool) -> Frame {
        guard let screen else { return frame }
        let scale = displayRect().width / screen.frame.width
        guard scale > 0 else { return frame }
        var next = frame
        if resize {
            next.width = max(min(CardSettings.minimumWidth, screen.visibleFrame.width), frame.width + delta.x / scale)
            next.height = max(min(CardSettings.minimumHeight, screen.visibleFrame.height), frame.height + delta.y / scale)
        } else { next.x += delta.x / scale; next.y += delta.y / scale }
        return next.contained(in: screen.visibleFrame)
    }
    override func mouseDown(with event: NSEvent) {
        guard editable else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let item = windows.first(where: { previewRect($0.frame).contains(point) }), let id = item.windowID else { selectedID = nil; needsDisplay = true; return }
        let rect = previewRect(item.frame)
        selectedID = id; window?.makeFirstResponder(self)
        drag = (id, point, item.frame, point.x > rect.maxX - 20 && point.y > rect.maxY - 20)
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let drag, let i = windows.firstIndex(where: { $0.windowID == drag.id }) else { return }
        let point = convert(event.locationInWindow, from: nil)
        let frame = transformed(drag.frame, delta: CGPoint(x: point.x - drag.start.x, y: point.y - drag.start.y), resize: drag.resize)
        windows[i].frame = frame; changed?(drag.id, frame); needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        defer { drag = nil }
        guard let drag, !drag.resize, let screen else { return }
        let point = convert(event.locationInWindow, from: nil), display = displayRect()
        let scale = display.width / screen.frame.width
        guard scale > 0 else { return }
        dropped?(drag.id, CGPoint(x: screen.frame.x + (point.x - display.minX) / scale, y: screen.frame.y + (point.y - display.minY) / scale))
    }
    /// The cards that can be selected, in the order they are drawn and read out (front first).
    var selectableIDs: [Int] { windows.compactMap(\.windowID) }
    func select(_ id: Int) { selectedID = id; window?.makeFirstResponder(self); updateAccessibility() }
    override func keyDown(with event: NSEvent) {
        guard editable else { super.keyDown(with: event); return }
        if event.keyCode == 48 { tab(backwards: event.modifierFlags.contains(.shift)); return }
        guard let id = selectedID, let item = windows.first(where: { $0.windowID == id }), let screen else { super.keyDown(with: event); return }
        let key: CardKey
        switch event.keyCode {
        case 123: key = .left
        case 124: key = .right
        case 125: key = .down
        case 126: key = .up
        default: super.keyDown(with: event); return
        }
        let resize = !event.modifierFlags.isDisjoint(with: [.shift, .option])
        changed?(id, CardKeys.apply(key, resize: resize, to: item.frame, in: screen.visibleFrame))
    }
    /// Tab goes to the next card; past the first or last card focus leaves the canvas.
    private func tab(backwards: Bool) {
        let ids = selectableIDs
        if let index = CardOrder.next(after: selectedID.flatMap { ids.firstIndex(of: $0) }, count: ids.count, backwards: backwards) {
            select(ids[index])
        } else {
            selectedID = nil; updateAccessibility()
            if backwards { window?.selectPreviousKeyView(self) } else { window?.selectNextKeyView(self) }
        }
    }
    /// One accessibility element per card; the canvas stays their group.
    private final class CardElement: NSAccessibilityElement {
        var onPress: () -> Void = {}
        override func accessibilityPerformPress() -> Bool { onPress(); return true }
    }
    private var cardElements: [CardElement] = []
    var screenNumber = 1
    override func accessibilityChildren() -> [Any]? { cardElements }
    func updateAccessibility() {
        setAccessibilityElement(true); setAccessibilityRole(.group)
        let count = windows.count == 1 ? Words.raw("canvas.windows.one") : Words.text("canvas.windows.other", windows.count)
        setAccessibilityLabel(Words.text("canvas.label", screen?.name ?? Words.raw("canvas.noScreen"), count, editable ? Words.raw("canvas.help.editable") : message))
        cardElements = windows.map { item in
            let element = CardElement()
            element.setAccessibilityParent(self); element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(item.app.isEmpty ? item.title : item.detail.isEmpty ? item.app : CardText.label(app: item.app, title: item.detail))
            element.setAccessibilityValue(CardText.value(item.frame, screenNumber: screenNumber))
            element.setAccessibilityFrameInParentSpace(previewRect(item.frame))
            element.setAccessibilitySelected(editable && item.windowID != nil && item.windowID == selectedID)
            if editable, let id = item.windowID { element.onPress = { [weak self] in self?.select(id) } }
            return element
        }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18).fill()
        guard let screen else { return }
        let display = displayRect(), desktop = NSBezierPath(roundedRect: display, xRadius: 10, yRadius: 10)
        NSGradient(colors: [NSColor(calibratedRed: 0.12, green: 0.19, blue: 0.36, alpha: 1), NSColor(calibratedRed: 0.20, green: 0.39, blue: 0.50, alpha: 1)])?.draw(in: desktop, angle: 45)
        NSGraphicsContext.saveGraphicsState(); desktop.addClip()
        let usable = previewRect(screen.visibleFrame)
        NSColor.white.withAlphaComponent(0.10).setFill(); NSBezierPath(rect: CGRect(x: display.minX, y: display.minY, width: display.width, height: max(0, usable.minY - display.minY))).fill()
        for item in windows.reversed() {
            let rect = previewRect(item.frame)
            guard rect.intersects(display) else { continue }
            let selected = editable && item.windowID != nil && item.windowID == selectedID
            let hue = Double(item.bundleID.utf8.reduce(0) { ($0 * 31 + Int($1)) % 360 }) / 360
            let color = NSColor(calibratedHue: hue, saturation: 0.40, brightness: 0.85, alpha: 1)
            let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.28); shadow.shadowBlurRadius = 7; shadow.shadowOffset = NSSize(width: 0, height: -2); shadow.set()
            NSColor.windowBackgroundColor.withAlphaComponent(0.97).setFill(); path.fill(); NSGraphicsContext.restoreGraphicsState()
            (selected ? NSColor.controlAccentColor : color).setStroke(); path.lineWidth = selected ? 3 : 1; path.stroke()
            NSGraphicsContext.saveGraphicsState(); path.addClip()
            color.withAlphaComponent(0.22).setFill(); NSBezierPath(rect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(32, rect.height))).fill()
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
            (item.title as NSString).draw(in: rect.insetBy(dx: 12, dy: 9), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
            if editable && rect.width > 35 && rect.height > 35 {
                let grip = NSBezierPath(); grip.move(to: CGPoint(x: rect.maxX - 16, y: rect.maxY - 5)); grip.line(to: CGPoint(x: rect.maxX - 5, y: rect.maxY - 16)); grip.move(to: CGPoint(x: rect.maxX - 10, y: rect.maxY - 5)); grip.line(to: CGPoint(x: rect.maxX - 5, y: rect.maxY - 10)); grip.lineWidth = 2; NSColor.secondaryLabelColor.setStroke(); grip.stroke()
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        if windows.isEmpty {
            let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
            (message as NSString).draw(in: CGRect(x: usable.minX + 30, y: usable.midY - 25, width: max(0, usable.width - 60), height: 65), withAttributes: [.font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.85), .paragraphStyle: paragraph])
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
