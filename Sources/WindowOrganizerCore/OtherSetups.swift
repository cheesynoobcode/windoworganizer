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

/// The words for an entry's setup: "2 screens, desktop 3 · Built-in + LG · 4 windows".
public enum OtherSetupLine {
    public static func text(_ entry: OtherSetupEntry, screens: [ScreenInfo]) -> String {
        let uuids = entry.screenUUIDs
        let names = uuids.map { uuid in screens.first { $0.uuid == uuid }?.name ?? "a screen not connected" }
        let count = uuids.count
        let windows = entry.windowCount
        return "\(count) \(count == 1 ? "screen" : "screens"), desktop \(entry.desktop) · \(names.joined(separator: " + ")) · \(windows) \(windows == 1 ? "window" : "windows")"
    }
}
