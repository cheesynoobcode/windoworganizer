import Foundation
import WindowOrganizerCore

// WO-GRID-BALANCED (Tom 5 Oct, decisions-open.md:29-30): Grid spreads windows evenly over the rows, row lengths differ by at
// most one, longer rows on top (4 = 2+2, 7 = 3+2+2, 8 = 3+3+2, 10 = 4+3+3); wider than 2:1 keeps the older wide-screen rule.

/// The number of windows in each row, top to bottom (each column, left to right, when `columns` is set).
private func lines(_ frames: [Frame], columns: Bool = false) -> [Int] {
    let starts = frames.map { columns ? $0.x : $0.y }
    return Set(starts).sorted().map { s in starts.filter { $0 == s }.count }
}

let gridChecks: [(String, @Sendable () throws -> Void)] = [
    ("grid on the built-in display: 4 windows = 2 by 2 with equal cells", {
        let frames = gridTile(4, in: laptop.visibleFrame)
        try expectEqual(lines(frames), [2, 2])
        try expectEqual(Set(frames.map(\.width)), [756])
        try expect(Set(frames.map(\.height)).count <= 2 && frames.allSatisfy { abs($0.height - 949.0 / 2) <= 1 }, "uneven rows \(frames)")
    }),
    ("grid on the built-in display: 1 through 10 windows give the most even rows (grid 1…10 table)", {
        let want: [[Int]] = [[1], [2], [2, 1], [2, 2], [3, 2], [3, 3], [3, 2, 2], [3, 3, 2], [3, 3, 3], [4, 3, 3]]
        for (i, rows) in want.enumerated() { try expectEqual(lines(gridTile(i + 1, in: laptop.visibleFrame)), rows) }
    }),
    ("grid keeps reading order: left to right, then the next row", {
        let frames = gridTile(5, in: laptop.visibleFrame)
        try expectEqual(frames.map(\.y), [33, 33, 33, 508, 508])
        try expectEqual(frames.map(\.x), [0, 504, 1008, 0, 756])
    }),
    ("grid 7 = 3+2+2 and 8 = 3+3+2: Tom's examples, longer rows on top", {
        try expectEqual(lines(gridTile(7, in: laptop.visibleFrame)), [3, 2, 2])
        try expectEqual(lines(gridTile(8, in: laptop.visibleFrame)), [3, 3, 2])
    }),
    ("grid wider than 2:1 keeps main's rule: 3 and 4 side by side at 2560 by 1080", {
        let wide = Frame(x: 0, y: 0, width: 2560, height: 1080)
        try expectEqual(gridTile(3, in: wide), [Frame(x: 0, y: 0, width: 853, height: 1080), Frame(x: 853, y: 0, width: 854, height: 1080),
                                                Frame(x: 1707, y: 0, width: 853, height: 1080)])
        try expectEqual(gridTile(4, in: wide), (0..<4).map { Frame(x: Double($0) * 640, y: 0, width: 640, height: 1080) })
    }),
    ("grid on a portrait screen is the same rule turned (engineering, not Tom's): columns instead of rows", {
        let tall = Frame(x: 0, y: 0, width: 949, height: 1512)
        try expectEqual(lines(gridTile(3, in: tall), columns: true), [2, 1])
        try expectEqual(lines(gridTile(4, in: tall), columns: true), [2, 2])
        try expectEqual(lines(gridTile(7, in: tall), columns: true), [3, 2, 2])
        try expectEqual(gridTile(3, in: tall).map(\.x), [0, 0, 475])
    }),
    ("grid tiles the area exactly with shared rounded edges, 1 through 20, landscape and portrait", {
        for area in [laptop.visibleFrame, Frame(x: 1512, y: 25, width: 1200, height: 800), Frame(x: 0, y: 0, width: 2560, height: 1080),
                     Frame(x: 0, y: 0, width: 949, height: 1512)] {
            for n in 1...20 {
                let frames = gridTile(n, in: area)
                try expectEqual(frames.count, n)
                try expect(frames.allSatisfy { $0.isValid && area.rect.contains($0.rect) && $0.x == $0.x.rounded() && $0.width == $0.width.rounded() }, "rounded and inside")
                try expectEqual(frames.reduce(0) { $0 + $1.width * $1.height }, area.width * area.height)
                for i in frames.indices {
                    for j in frames.indices where j > i {
                        let r = frames[i].rect.intersection(frames[j].rect)
                        try expect(r.isNull || r.width == 0 || r.height == 0, "tiles overlap at n = \(n)")
                    }
                }
            }
        }
    }),
    ("grid at exactly 2:1 takes the even rows, just wider keeps main's rule (Tom: wider than 2:1)", {
        try expectEqual(lines(gridTile(3, in: Frame(x: 0, y: 0, width: 2000, height: 1000))), [2, 1])
        try expectEqual(lines(gridTile(3, in: Frame(x: 0, y: 0, width: 2001, height: 1000))), [3])
    }),
    ("grid with gap 8 on uneven rows 3+2+2 and 3+3+2: inside, no overlap, every neighbour exactly 8 apart", {
        let area = laptop.visibleFrame
        for n in [7, 8] {
            let gapped = applyGap(gridTile(n, in: area), gap: 8)
            try expect(!gapped.skipped, "gap skipped at n = \(n)")
            let frames = gapped.frames
            try expect(frames.allSatisfy { area.rect.contains($0.rect) }, "outside at n = \(n)")
            for i in frames.indices {
                for j in frames.indices where j > i {
                    try expect(frames[i].rect.intersection(frames[j].rect).isNull, "overlap at n = \(n)")
                }
            }
            for row in Set(frames.map(\.y)).sorted() {
                let cells = frames.filter { $0.y == row }.sorted { $0.x < $1.x }
                for (a, b) in zip(cells, cells.dropFirst()) { try expectEqual(b.x - (a.x + a.width), 8) }
            }
            let rows = Set(frames.map(\.y)).sorted().map { y in frames.first { $0.y == y }! }
            for (a, b) in zip(rows, rows.dropFirst()) { try expectEqual(b.y - (a.y + a.height), 8) }
        }
    }),
    ("grid callers: preset Grid, a tiled group, Restore on an auto-tile screen and the immediate grid all give 7 = 3+2+2", {
        let anywhere = Frame(x: 900, y: 300, width: 400, height: 300)
        let ws = (1...7).map { window($0, term, "w\($0)", $0 - 1, anywhere) }
        func placed(_ p: Plan?) -> [Frame] { (p?.moves ?? []).sorted { $0.windowID < $1.windowID }.map(\.to) }
        try expectEqual(lines(presetFrames(.grid, count: 7, in: laptop.visibleFrame)), [3, 2, 2])
        let g = WindowGroup(id: "g", name: "G", members: [ZoneMember(bundleID: term)], screen: "MBP", desktops: [1], mode: .tiled)
        try expectEqual(lines(placed(planGroups([g], windows: ws, screen: laptop, settings: ArrangeSettings()))), [3, 2, 2])
        var l = Layouts()
        l.set(ScreenArrangement(kind: .autoTile), setup: ScreenSetup(screens: [laptop]), desktop: 1, screen: "MBP")
        try expectEqual(lines(placed(planRestore(l, windows: ws, screens: [laptop], desktops: ["MBP": 1]))), [3, 2, 2])
        let sel = WorkspaceSelection(screenUUID: "MBP", desktop: 1)
        try expectEqual(lines(placed(try planAutomaticWorkspace(sel, windows: ws, screens: [laptop], desktops: ["MBP": 1]))), [3, 2, 2])
    }),
]
