import Foundation
import WindowOrganizerCore

// GPT-WO-S8: each window card on the canvas is its own accessibility element, and the arrow keys move or resize it.

private let area = Frame(x: 0, y: 25, width: 1440, height: 875)
private let card = Frame(x: 100, y: 200, width: 400, height: 300)
private let step = CardSettings.step

let cardKeyChecks: [(String, @Sendable () throws -> Void)] = [
    ("card keys: each arrow moves the card by one step", {
        try expectEqual(CardKeys.apply(.left, resize: false, to: card, in: area), Frame(x: 100 - step, y: 200, width: 400, height: 300))
        try expectEqual(CardKeys.apply(.right, resize: false, to: card, in: area), Frame(x: 100 + step, y: 200, width: 400, height: 300))
        try expectEqual(CardKeys.apply(.up, resize: false, to: card, in: area), Frame(x: 100, y: 200 - step, width: 400, height: 300))
        try expectEqual(CardKeys.apply(.down, resize: false, to: card, in: area), Frame(x: 100, y: 200 + step, width: 400, height: 300))
    }),
    ("card keys: shift plus an arrow resizes by the same step and keeps the corner", {
        try expectEqual(CardKeys.apply(.right, resize: true, to: card, in: area), Frame(x: 100, y: 200, width: 400 + step, height: 300))
        try expectEqual(CardKeys.apply(.left, resize: true, to: card, in: area), Frame(x: 100, y: 200, width: 400 - step, height: 300))
        try expectEqual(CardKeys.apply(.down, resize: true, to: card, in: area), Frame(x: 100, y: 200, width: 400, height: 300 + step))
        try expectEqual(CardKeys.apply(.up, resize: true, to: card, in: area), Frame(x: 100, y: 200, width: 400, height: 300 - step))
    }),
    ("card keys: a move stops at the screen edge instead of leaving the screen", {
        let left = Frame(x: 2, y: 200, width: 400, height: 300)
        try expectEqual(CardKeys.apply(.left, resize: false, to: left, in: area).x, 0)
        let bottom = Frame(x: 100, y: 25 + 875 - 300 - 1, width: 400, height: 300)
        try expectEqual(CardKeys.apply(.down, resize: false, to: bottom, in: area).y, 25 + 875 - 300)
    }),
    ("card keys: a resize never goes below the minimum size or past the screen edge", {
        let small = Frame(x: 100, y: 200, width: CardSettings.minimumWidth, height: CardSettings.minimumHeight)
        try expectEqual(CardKeys.apply(.left, resize: true, to: small, in: area), small)
        try expectEqual(CardKeys.apply(.up, resize: true, to: small, in: area), small)
        let wide = Frame(x: 1440 - 400, y: 200, width: 400, height: 300)
        try expectEqual(CardKeys.apply(.right, resize: true, to: wide, in: area).width, 400)
    }),
    ("card text: the label is app and title, the value is position, size and screen number", {
        try expectEqual(CardText.label(app: "Safari", title: "Apple"), "Safari — Apple")
        try expectEqual(CardText.value(card, screenNumber: 2), "100, 200, 400 × 300 on screen 2")
    }),
    ("card text: the wording comes from words.json, not from code", {
        try expectEqual(CardText.label(app: "A", title: "B"), String(format: Words.raw("card.label"), "A", "B"))
        try expectEqual(Words.raw("card.value"), "%d, %d, %d × %d on screen %d")
        for key in ["card.label", "card.value", "canvas.noScreen", "canvas.windows.one", "canvas.windows.other", "canvas.label", "canvas.help.editable",
                    "card.step", "card.minimumWidth", "card.minimumHeight"] { try expect(Words.has(key), "words.json lacks \(key)") }
        try expectEqual(CardSettings.step, 4)
    }),
    ("card order: Tab goes to the next card, shift-Tab to the previous, and leaves the canvas at the ends", {
        try expectEqual(CardOrder.next(after: nil, count: 3, backwards: false), 0)
        try expectEqual(CardOrder.next(after: 0, count: 3, backwards: false), 1)
        try expectEqual(CardOrder.next(after: 2, count: 3, backwards: false), nil)
        try expectEqual(CardOrder.next(after: 2, count: 3, backwards: true), 1)
        try expectEqual(CardOrder.next(after: 0, count: 3, backwards: true), nil)
        try expectEqual(CardOrder.next(after: nil, count: 3, backwards: true), 2)
        try expectEqual(CardOrder.next(after: nil, count: 0, backwards: false), nil)
    }),
]
