import Foundation

/// GPT-WO-S8: the numbers behind the canvas cards; they live in words.json.
public enum CardSettings {
    public static var step: Double { Words.number("card.step") }
    public static var minimumWidth: Double { Words.number("card.minimumWidth") }
    public static var minimumHeight: Double { Words.number("card.minimumHeight") }
}

public enum CardKey: Sendable { case left, right, up, down }

public enum CardKeys {
    /// One arrow key on a window card: it moves the card, or resizes it (right/down grow, left/up shrink, the top-left
    /// corner stays). The result stays inside `area`, and a resize never goes below the minimum size.
    public static func apply(_ key: CardKey, resize: Bool, to frame: Frame, in area: Frame) -> Frame {
        let dx: Double, dy: Double
        switch key {
        case .left: (dx, dy) = (-CardSettings.step, 0)
        case .right: (dx, dy) = (CardSettings.step, 0)
        case .up: (dx, dy) = (0, -CardSettings.step)
        case .down: (dx, dy) = (0, CardSettings.step)
        }
        var next = frame
        if resize {
            next.width = min(max(frame.width + dx, min(CardSettings.minimumWidth, frame.width)), max(frame.width, area.x + area.width - frame.x))
            next.height = min(max(frame.height + dy, min(CardSettings.minimumHeight, frame.height)), max(frame.height, area.y + area.height - frame.y))
            return next
        }
        next.x += dx; next.y += dy
        return next.contained(in: area)
    }
}

public enum CardText {
    public static func label(app: String, title: String) -> String { Words.text("card.label", app, title) }
    /// The card's real position and size on its screen, not its size on the canvas.
    public static func value(_ frame: Frame, screenNumber: Int) -> String {
        Words.text("card.value", Int(frame.x.rounded()), Int(frame.y.rounded()), Int(frame.width.rounded()), Int(frame.height.rounded()), screenNumber)
    }
}

public enum CardOrder {
    /// The card Tab (or shift-Tab) goes to from `current`, or nil when focus leaves the canvas.
    public static func next(after current: Int?, count: Int, backwards: Bool) -> Int? {
        guard count > 0 else { return nil }
        let target = current.map { backwards ? $0 - 1 : $0 + 1 } ?? (backwards ? count - 1 : 0)
        return (0..<count).contains(target) ? target : nil
    }
}
