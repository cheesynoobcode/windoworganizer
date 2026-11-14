import Foundation
import WindowOrganizerCore

// GPT-WO-S7: layouts saved for another screen setup or desktop are listed read-only; "Use here" copies one into the
// current screen and desktop, never replaces anything and never touches the original.

private func screen(_ uuid: String, _ name: String) -> ScreenInfo {
    let f = Frame(x: 0, y: 0, width: 1440, height: 900)
    return ScreenInfo(uuid: uuid, name: name, frame: f, visibleFrame: f)
}

private let builtIn = screen("A", "Built-in")
private let lg = screen("B", "LG")
private let one = ScreenSetup(screens: [builtIn])
private let two = ScreenSetup(screens: [builtIn, lg])

private func snapshot(_ bundles: [String]) -> ScreenArrangement {
    let f = Frame(x: 0, y: 0, width: 100, height: 100)
    let r = UnitRect(x: 0, y: 0, width: 0.5, height: 1)
    return ScreenArrangement(kind: .snapshot(bundles.map {
        Placement(matcher: Matcher(bundleID: $0), fraction: r, pixel: f, screenUUID: "A", visibleFrame: f)
    }))
}

private func sample() -> Layouts {
    var l = Layouts()
    l.set(snapshot(["com.a"]), setup: one, desktop: 2, screen: "A")
    l.set(snapshot(["com.a", "com.b", "com.c", "com.d"]), setup: two, desktop: 3, screen: "A")
    l.set(snapshot(["com.e"]), setup: one, desktop: 1, screen: "A")
    return l
}

let otherSetupChecks: [(String, @Sendable () throws -> Void)] = [
    ("other setups: the current setup and desktop are not listed; another desktop and another setup are", {
        let found = sample().otherEntries(current: one, desktop: 2)
        try expectEqual(found.map { "\($0.setupKey)|\($0.desktop)" }, ["A|1", "A+B|3"])
    }),
    ("other setups: the line says screens, desktop, screen names, the source screen and window count", {
        let entry = sample().otherEntries(current: one, desktop: 2).last!
        try expectEqual(OtherSetupLine.text(entry, screens: [builtIn, lg]), "2 screens, desktop 3 · Built-in + LG · layout for Built-in · 4 windows")
    }),
    ("other setups: a screen that is not connected is named as such", {
        let entry = sample().otherEntries(current: one, desktop: 2).last!
        try expectEqual(OtherSetupLine.text(entry, screens: [builtIn]), "2 screens, desktop 3 · Built-in + a screen not connected · layout for Built-in · 4 windows")
    }),
    ("other setups: Use here copies to this screen and desktop and leaves the original byte-equal", {
        var l = sample()
        let entry = l.otherEntries(current: one, desktop: 2).last!
        l.remove(setup: one, desktop: 2, screen: "A")
        let before = l.setups[entry.setupKey]
        try expect(l.useHere(entry, setup: one, desktop: 2, screen: "A") == nil, "copy refused")
        try expectEqual(l.arrangement(setup: one, desktop: 2, screen: "A"), entry.arrangement)
        try expectEqual(l.setups[entry.setupKey], before)
    }),
    ("other setups: an occupied target is refused and nothing changes", {
        var l = sample()
        let entry = l.otherEntries(current: one, desktop: 2).last!
        let before = l
        try expectEqual(l.useHere(entry, setup: one, desktop: 2, screen: "A"), .occupied)
        try expectEqual(l, before)
    }),
    ("other setups: copying onto the entry's own place is refused", {
        var l = sample()
        let entry = l.otherEntries(current: one, desktop: 2).last!
        let before = l
        try expectEqual(l.useHere(entry, setup: two, desktop: 3, screen: "A"), .sameSlot)
        try expectEqual(l, before)
    }),
    ("other setups: connected screens are named first, then the one that is not connected", {
        let entry = sample().otherEntries(current: one, desktop: 2).last!
        try expectEqual(OtherSetupLine.text(entry, screens: [lg]), "2 screens, desktop 3 · LG + a screen not connected · layout for a screen not connected · 4 windows")
    }),
    ("other words: one and other counts come from words.json", {
        try expectEqual(Words.count("other.screens", 1), "1 screen")
        try expectEqual(Words.count("other.screens", 2), "2 screens")
        try expectEqual(Words.count("canvas.windows", 1), "1 window")
        try expectEqual(Words.count("canvas.windows", 2), "2 windows")
        try expectEqual(Words.count("canvas.windows", 0), "0 windows")
        try expectEqual(Words.raw("other.screens.one"), "1 screen")
        try expectEqual(Words.raw("canvas.windows.other"), "%d windows")
    }),
    ("other words: placeholders in the file take the arguments in the order the code passes them", {
        try expectEqual(Words.raw("other.confirm.question"), "Copy this layout to %@, %@?")
        try expectEqual(Words.text("other.confirm.question", "LG", "Desktop 2"), "Copy this layout to LG, Desktop 2?")
        try expectEqual(Words.text("other.copied", "LG", "Desktop 2"), "Copied to LG, Desktop 2. The other layout is unchanged.")
        try expectEqual(Words.text("other.taken.line", "LG", "Desktop 2"), "LG, Desktop 2 already has a layout, so Use here is off. Nothing is replaced.")
        try expectEqual(Words.text("other.taken.tip", "LG", "Desktop 2"), "LG, Desktop 2 already has a layout. Nothing is replaced.")
        try expectEqual(Words.text("other.line", "2 screens", 3, "A + B", "A", "4 windows"), "2 screens, desktop 3 · A + B · layout for A · 4 windows")
        for key in ["other.confirm.question", "other.copied", "other.taken.line", "other.taken.tip", "other.reason.occupied"] {
            try expectEqual(Words.raw(key).components(separatedBy: "%@").count - 1, 2)
        }
    }),
    ("other words: every key the code asks Words for is in words.json", {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let call = try NSRegularExpression(pattern: #"Words\.(raw|has|text|number|count)\(\s*"([^"]+)""#)
        var seen = 0
        for case let url as URL in FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)! where url.pathExtension == "swift" && !url.path.contains("/WOChecks/") {
            let code = try String(contentsOf: url, encoding: .utf8)
            for m in call.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                let kind = String(code[Range(m.range(at: 1), in: code)!]), key = String(code[Range(m.range(at: 2), in: code)!])
                seen += 1
                let keys = kind == "count" ? [key + ".one", key + ".other"] : [key]
                for k in keys { try expect(Words.has(k), "\(url.lastPathComponent): words.json lacks \(k)") }
            }
        }
        try expect(seen >= 15, "the scan found only \(seen) Words calls")
    }),
    ("other setups: Cancel writes nothing, the layout file stays byte-equal", {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wo-other-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LayoutStore(directory: dir)
        var l = sample(); l.remove(setup: one, desktop: 2, screen: "A")
        try store.save(l)
        let entry = l.otherEntries(current: one, desktop: 2).last!
        let before = try Data(contentsOf: store.file)
        var asked = 0
        let outcome = store.useHere(entry, setup: one, desktop: 2, screen: "A", dirty: false, confirm: { asked += 1; return false })
        try expectEqual(outcome, .cancelled)
        try expectEqual(asked, 1)
        try expectEqual(try Data(contentsOf: store.file), before)
        try expect(!FileManager.default.fileExists(atPath: store.previous.path), "a cancelled copy made a backup")
        try expectEqual(outcome.line(screen: "Built-in", desktop: "Desktop 2"), nil)
        // and Yes copies, so the check above is not passing for want of a copy
        try expectEqual(store.useHere(entry, setup: one, desktop: 2, screen: "A", dirty: false, confirm: { true }), .copied)
        try expect(try store.load().arrangement(setup: one, desktop: 2, screen: "A") != nil, "Yes did not copy")
    }),
    ("other setups: unsaved changes refuse before asking, and every outcome has its line from the file", {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wo-other-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LayoutStore(directory: dir)
        try store.save(sample())
        let entry = sample().otherEntries(current: one, desktop: 2).last!
        var asked = false
        try expectEqual(store.useHere(entry, setup: one, desktop: 2, screen: "A", dirty: true, confirm: { asked = true; return true }), .dirty)
        try expect(!asked, "asked with unsaved changes")
        try expectEqual(UseHereOutcome.dirty.line(screen: "S", desktop: "D"), "Not copied: save or revert your changes here first.")
        try expectEqual(UseHereOutcome.refused(.occupied).line(screen: "S", desktop: "D 2"), "Not copied: S, D 2 already has a layout.")
        try expectEqual(UseHereOutcome.refused(.sameSlot).line(screen: "S", desktop: "D"), "Not copied: that is this layout.")
        try expectEqual(UseHereOutcome.copied.line(screen: "S", desktop: "D 2"), "Copied to S, D 2. The other layout is unchanged.")
        try expectEqual(UseHereOutcome.failed("disk full").line(screen: "S", desktop: "D"), "Not copied: disk full")
        try expectEqual(store.useHere(entry, setup: one, desktop: 2, screen: "A", dirty: false, confirm: { true }), .refused(.occupied))
    }),
    ("other setups: rules, gap and groups are the same after a copy, on both sides", {
        var l = sample()
        l.setRule(AppRule(bundleID: "com.rule", desktop: 2, screen: "A", area: UnitRect(x: 0, y: 0, width: 0.5, height: 1)))
        l.setArrangeSettings(ArrangeSettings(gap: 12, sortByName: true), desktop: 3, screen: "A")
        l.setArrangeSettings(ArrangeSettings(gap: 4, sortByName: false), desktop: 2, screen: "A")
        l.setGroup(WindowGroup(id: "g1", name: "Work", members: [ZoneMember(bundleID: "com.a")], screen: "A", desktops: [2, 3], mode: .tiled))
        let entry = l.otherEntries(current: one, desktop: 2).last!
        l.remove(setup: one, desktop: 2, screen: "A")
        let (rules, arrange, groups, source) = (l.rules, l.arrange, l.groups, l.setups[entry.setupKey])
        try expect(l.useHere(entry, setup: one, desktop: 2, screen: "A") == nil, "copy refused")
        try expectEqual(l.rules, rules)
        try expectEqual(l.arrange, arrange)
        try expectEqual(l.groups, groups)
        try expectEqual(l.setups[entry.setupKey], source)
    }),
    ("other setups: a taken target shows its reason in words, a free one shows none", {
        try expectEqual(OtherSetupLine.takenLine(taken: true, screen: "LG", desktop: "Desktop 2"), "LG, Desktop 2 already has a layout, so Use here is off. Nothing is replaced.")
        try expectEqual(OtherSetupLine.takenTip(taken: true, screen: "LG", desktop: "Desktop 2"), "LG, Desktop 2 already has a layout. Nothing is replaced.")
        try expectEqual(OtherSetupLine.takenLine(taken: false, screen: "LG", desktop: "Desktop 2"), nil)
        try expectEqual(OtherSetupLine.takenTip(taken: false, screen: "LG", desktop: "Desktop 2"), nil)
    }),
]
