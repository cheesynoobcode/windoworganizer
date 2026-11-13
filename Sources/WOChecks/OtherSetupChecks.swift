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
    ("other setups: the line says screens, desktop, screen names and window count", {
        let entry = sample().otherEntries(current: one, desktop: 2).last!
        try expectEqual(OtherSetupLine.text(entry, screens: [builtIn, lg]), "2 screens, desktop 3 · Built-in + LG · 4 windows")
    }),
    ("other setups: a screen that is not connected is named as such", {
        let entry = sample().otherEntries(current: one, desktop: 2).last!
        try expectEqual(OtherSetupLine.text(entry, screens: [builtIn]), "2 screens, desktop 3 · Built-in + a screen not connected · 4 windows")
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
]
