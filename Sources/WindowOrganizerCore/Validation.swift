import Foundation

extension Layouts {
    /// Reject malformed imported or hand-edited geometry before it can move any window.
    public func validate() throws {
        guard schema == Self.currentSchema else { throw LayoutStoreError.unsupportedSchema(schema) }
        func require(_ good: Bool) throws { if !good { throw LayoutStoreError.invalidLayout } }
        for desktops in setups.values {
            for (desktop, screens) in desktops {
                try require(Int(desktop).map { $0 >= 0 && $0 <= 1000 } ?? false)
                for (screen, arrangement) in screens {
                    try require(!screen.isEmpty)
                    switch arrangement.kind {
                    case .snapshot(let places):
                        for p in places {
                            try require(!p.matcher.bundleID.isEmpty && p.matcher.order >= 0 && p.pixel.isValid && p.visibleFrame.isValid && p.fraction.isValid && p.screenUUID == screen)
                        }
                    case .zones(let zones):
                        for z in zones {
                            try require(z.rect.isWithinUnit && z.members.allSatisfy { !$0.bundleID.isEmpty })
                        }
                    case .autoTile: break
                    }
                }
            }
        }
        for (desktop, screens) in arrange {
            try require(Int(desktop).map { $0 >= 0 && $0 <= 1000 } ?? false)
            for (screen, settings) in screens { try require(!screen.isEmpty && (0...ArrangeSettings.maxGap).contains(settings.gapPoints))
                try require((settings.manualOrder?.count ?? 0) <= ArrangeSettings.maxManualOrder && (settings.manualOrder ?? []).allSatisfy { !$0.bundleID.isEmpty })
            }
        }
        try validateGroups()
        try require(Set(rules.map(\.bundleID)).count == rules.count)
        for rule in rules { try require(!rule.bundleID.isEmpty && !rule.screen.isEmpty && rule.desktop >= 0 && rule.desktop <= 1000 && rule.area.isWithinUnit) }
    }
}

/// Grid's wide-screen rule applies on screens wider than this width/height ratio.
/// Tom 5 Oct 09:3x (decisions-open.md): "on screens wider than 2:1 Grid keeps today's wide-screen rule".
public let gridWideRatio = 2.0

/// A compact grid for all windows of a screen, with shared rounded edges and no empty cells.
/// Tom 5 Oct 09:3x: windows are spread evenly over the rows, row lengths differ by at most one, longer rows on top
/// (7 → 3+2+2, 8 → 3+3+2, 10 → 4+3+3); rows = ceil(n / ceil(sqrt n)). A portrait area turns this 90°: columns, filled
/// left to right, longer columns first. Wider than gridWideRatio keeps the wide-screen rule (columns by aspect ratio).
public func gridTile(_ n: Int, in area: Frame) -> [Frame] {
    guard n > 0, area.isValid else { return [] }
    if area.width / area.height > gridWideRatio { return wideGridTile(n, in: area) }
    let lines = Int(ceil(Double(n) / ceil(sqrt(Double(n)))))
    let portrait = area.height > area.width
    var frames: [Frame] = []
    for line in 0..<lines {
        let count = n / lines + (line < n % lines ? 1 : 0)
        // across = the line's own axis split `count` ways; along = the lines' axis split `lines` ways.
        let (along0, alongSize, across0, acrossSize) = portrait
            ? (area.x, area.width, area.y, area.height) : (area.y, area.height, area.x, area.width)
        let a0 = (along0 + Double(line) * alongSize / Double(lines)).rounded()
        let a1 = (along0 + Double(line + 1) * alongSize / Double(lines)).rounded()
        for cell in 0..<count {
            let c0 = (across0 + Double(cell) * acrossSize / Double(count)).rounded()
            let c1 = (across0 + Double(cell + 1) * acrossSize / Double(count)).rounded()
            frames.append(portrait ? Frame(x: a0, y: c0, width: a1 - a0, height: c1 - c0) : Frame(x: c0, y: a0, width: c1 - c0, height: a1 - a0))
        }
    }
    return frames
}

/// The wide-screen rule (main before WO-GRID-BALANCED): columns by aspect ratio, the last row spread over the full width.
private func wideGridTile(_ n: Int, in area: Frame) -> [Frame] {
    let columns = min(n, max(1, Int(ceil(sqrt(Double(n) * area.width / area.height)))))
    let rows = Int(ceil(Double(n) / Double(columns)))
    var frames: [Frame] = []
    for row in 0..<rows {
        let count = min(columns, n - row * columns)
        let y0 = (area.y + Double(row) * area.height / Double(rows)).rounded()
        let y1 = (area.y + Double(row + 1) * area.height / Double(rows)).rounded()
        for col in 0..<count {
            let x0 = (area.x + Double(col) * area.width / Double(count)).rounded()
            let x1 = (area.x + Double(col + 1) * area.width / Double(count)).rounded()
            frames.append(Frame(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
        }
    }
    return frames
}
