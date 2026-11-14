import Foundation

/// One stored arrangement that belongs to another screen setup or desktop than the one in front of the user (GPT-WO-S7).
public struct OtherSetupEntry: Equatable, Sendable {
    public let setupKey: String
    public let desktop: Int
    public let screenUUID: String
    public let arrangement: ScreenArrangement

    /// The screens of the setup, from its key.
    public var screenUUIDs: [String] { setupKey.split(separator: "+").map(String.init) }

    public var windowCount: Int {
        switch arrangement.kind {
        case .snapshot(let placements): return placements.count
        case .zones(let zones): return zones.reduce(0) { $0 + $1.members.count }
        case .autoTile: return 0
        }
    }
}

public enum UseHereRefusal: Equatable, Sendable {
    /// The entry is the target itself.
    case sameSlot
    /// The target already holds an arrangement; nothing is replaced.
    case occupied
}

extension Layouts {
    /// Everything stored outside (current setup, this desktop), oldest setup key first, then by desktop and screen.
    public func otherEntries(current: ScreenSetup, desktop: Int) -> [OtherSetupEntry] {
        var found: [OtherSetupEntry] = []
        for setupKey in setups.keys.sorted() {
            for (d, screens) in (setups[setupKey] ?? [:]).compactMap({ key, value in Int(key).map { ($0, value) } }).sorted(by: { $0.0 < $1.0 }) {
                if setupKey == current.key && d == desktop { continue }
                for uuid in screens.keys.sorted() {
                    found.append(OtherSetupEntry(setupKey: setupKey, desktop: d, screenUUID: uuid, arrangement: screens[uuid]!))
                }
            }
        }
        return found
    }

    /// Copies the entry's arrangement to this screen and desktop. The original is never touched, and an occupied
    /// target is never replaced. Returns why nothing was copied, or nil.
    public mutating func useHere(_ entry: OtherSetupEntry, setup: ScreenSetup, desktop: Int, screen: String) -> UseHereRefusal? {
        if entry.setupKey == setup.key && entry.desktop == desktop && entry.screenUUID == screen { return .sameSlot }
        if arrangement(setup: setup, desktop: desktop, screen: screen) != nil { return .occupied }
        set(entry.arrangement, setup: setup, desktop: desktop, screen: screen)
        return nil
    }
}

/// The words for an entry's setup: "2 screens, desktop 3 · Built-in + LG · layout for LG · 4 windows". Connected screens come first.
public enum OtherSetupLine {
    public static func text(_ entry: OtherSetupEntry, screens: [ScreenInfo]) -> String {
        let uuids = entry.screenUUIDs
        func name(_ uuid: String) -> String? { screens.first { $0.uuid == uuid }?.name }
        let known = uuids.compactMap(name), unknown = uuids.filter { name($0) == nil }.map { _ in Words.raw("other.screen.unknown") }
        return Words.text("other.line", Words.count("other.screens", uuids.count), entry.desktop, (known + unknown).joined(separator: " + "),
                          name(entry.screenUUID) ?? Words.raw("other.screen.unknown"), Words.count("canvas.windows", entry.windowCount))
    }
}

extension OtherSetupLine {
    /// The visible reason the buttons are off; nil while the target is free.
    public static func takenLine(taken: Bool, screen: String, desktop: String) -> String? {
        taken ? Words.text("other.taken.line", screen, desktop) : nil
    }
    public static func takenTip(taken: Bool, screen: String, desktop: String) -> String? {
        taken ? Words.text("other.taken.tip", screen, desktop) : nil
    }
}

/// What a press on "Use here" did, and the line the editor shows for it.
public enum UseHereOutcome: Equatable, Sendable {
    case copied, cancelled, dirty, refused(UseHereRefusal), failed(String)

    public func line(screen: String, desktop: String) -> String? {
        switch self {
        case .cancelled: return nil
        case .copied: return Words.text("other.copied", screen, desktop)
        case .dirty: return Words.text("other.notCopied", Words.raw("other.reason.dirty"))
        case .refused(.occupied): return Words.text("other.notCopied", Words.text("other.reason.occupied", screen, desktop))
        case .refused(.sameSlot): return Words.text("other.notCopied", Words.raw("other.reason.same"))
        case .failed(let why): return Words.text("other.notCopied", why)
        }
    }
}

extension LayoutStore {
    /// Asks first; "No" returns before anything is read or written. The stored layouts are loaded fresh, so a copy never
    /// carries a stale editor state, and only the target slot is added.
    public func useHere(_ entry: OtherSetupEntry, setup: ScreenSetup, desktop: Int, screen: String, dirty: Bool, confirm: () -> Bool) -> UseHereOutcome {
        if dirty { return .dirty }
        guard confirm() else { return .cancelled }
        do {
            var fresh = try load()
            if let why = fresh.useHere(entry, setup: setup, desktop: desktop, screen: screen) { return .refused(why) }
            try save(fresh)
            return .copied
        } catch { return .failed("\(error)") }
    }
}
