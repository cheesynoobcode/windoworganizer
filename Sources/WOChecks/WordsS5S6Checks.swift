import Foundation
import WindowOrganizerCore

// WO-WORDS-S5S6: the S5 (reading windows) and S6 (partial restore) words, and the older restore-line words, live in words.json.

let wordsS5S6Checks: [(String, @Sendable () throws -> Void)] = [
    ("restore words: every failure reason has its key in words.json", {
        for r in FailReason.allCases { try expect(Words.has("restore.reason." + r.rawValue), "words.json lacks the reason \(r.rawValue)") }
        try expectEqual(ResultLine.reasonText(.notAnswering), "not answering")
        try expectEqual(ResultLine.reasonText(.refusedSize), "refused the size")
        try expectEqual(ResultLine.reasonText(.gone), "gone")
    }),
    ("restore words: placeholders take the arguments in the order the code passes them", {
        try expectEqual(Words.text("restore.stopped", 3, 2, "08:00"), "Stopped: the desktop changed. Placed 3, 2 left as they were · 08:00")
        try expectEqual(Words.text("restore.noneOpen.one", 1), "none of the 1 remembered window is open")
        try expectEqual(Words.text("restore.noneOpen.other", 4), "none of the 4 remembered windows is open")
        try expectEqual(Words.text("restore.placed", "2 windows"), "2 windows placed")
        try expectEqual(Words.text("restore.minimum.one", 1), "1 kept its minimum size")
        try expectEqual(Words.text("restore.minimum.other", 2), "2 kept their minimum size")
        try expectEqual(Words.text("restore.moved.one", 1, ": Mail"), "1 kept its minimum size and was moved inside the screen: Mail")
        try expectEqual(Words.text("restore.moved.other", 2, ": Mail, Editor"), "2 kept their minimum size and were moved inside the screen: Mail, Editor")
        try expectEqual(Words.text("restore.failed", 2) + Words.text("restore.failed.list", "Mail (gone)"), "2 could not be moved (Mail (gone))")
        try expectEqual(Words.text("restore.notOpen", 3), "3 not open")
        try expectEqual(Words.text("restore.starting", "Mail, Notes"), "starting Mail, Notes")
        try expectEqual(Words.text("restore.line", "Desktop 1", "1 window placed", "08:00"), "Desktop 1: 1 window placed · 08:00")
        try expectEqual(Words.text("restore.entry", "Mail", " \"Inbox\"", "gone"), "Mail \"Inbox\" (gone)")
        try expectEqual(Words.text("restore.more", 3), ", and 3 more")
        try expectEqual(Words.text("desktop.number", 2), "Desktop 2")
        try expectEqual(Words.raw("desktop.unknown"), "Desktop unknown")
        try expectEqual(Words.text("group.stopped", "Work", 3, 2, "08:00"), "Stopped: the desktop changed. Group Work: 3 placed, 2 left as they were · 08:00")
        try expectEqual(Words.text("group.later.one", "2"), "Desktop 2 on next visit")
        try expectEqual(Words.text("group.later.other", "2, 3"), "Desktops 2, 3 on next visit")
        try expectEqual(Words.text("group.line", "Desktop 1", "Work", "1 window placed", "08:00"), "Desktop 1: Group Work: 1 window placed · 08:00")
    }),
    ("restore words: the failure list reads app, title and reason, and a window that is not listed is 'a window'", {
        let from = Frame(x: 0, y: 0, width: 300, height: 300)
        let windows = [window(1, term, "T1", 1, from), window(2, term, "", 2, from)]
        let failures = [(1, FailReason.notAnswering), (2, .gone), (9, .refusedSize)].map { FailedMove(move: Move(windowID: $0.0, from: from, to: from), reason: $0.1) }
        try expectEqual(ResultLine.notMoved(failures, in: windows),
                        "\(term) \"T1\" (not answering), \(term) (gone), a window (refused the size)")
    }),
    ("read and partial words: placeholders take the arguments in the order the code passes them", {
        try expectEqual(Words.raw("read.reading"), "Reading windows…")
        try expectEqual(Words.text("read.refreshed", 1), "Refreshed · 1 windows · Live positions reloaded.")
        try expectEqual(Words.text("read.unavailable", "no access"), "Refresh unavailable: no access")
        try expectEqual(Words.text("read.someUnavailable", "A. B."), "Some windows unavailable: A. B.")
        try expectEqual(Words.raw("read.noAccess"), "Enable window access in Accessibility settings first.")
        try expectEqual(Words.raw("read.noWindows"), "No standard windows are visible on this screen.")
        try expectEqual(Words.raw("partial.retry"), "Try these again")
        try expectEqual(Words.text("partial.notSaved", Words.text("partial.notSaved.moved", ": Mail (gone)")),
                        "Not saved: Some windows could not be moved: Mail (gone). Your preview is still here; try again.")
        try expectEqual(Words.raw("partial.saveGrid"), ". Save to keep this screen's automatic grid.")
        try expectEqual(Words.text("partial.list", "Mail (gone)"), ": Mail (gone)")
        try expectEqual(Words.text("partial.triedAgain", "Desktop 1: 1 placed · 08:00"), "Tried again: Desktop 1: 1 placed · 08:00")
        try expectEqual(Words.text("partial.notTriedAgain", "boom"), "Not tried again: boom")
        for key in ["read.unavailable", "read.someUnavailable", "partial.notSaved", "partial.notSaved.moved", "partial.list", "partial.triedAgain", "partial.notTriedAgain"] {
            try expectEqual(Words.raw(key).components(separatedBy: "%@").count - 1, 1)
        }
    }),
    ("restore words: every key quoted in the restore and layouts code is in words.json, also inside a ternary", {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let quoted = try NSRegularExpression(pattern: #""((?:read|partial|restore|group|desktop)(?:\.[A-Za-z]+)+)""#)
        var seen = 0
        for file in ["WindowOrganizerCore/Restore.swift", "WindowOrganizer/LayoutsWindow.swift"] {
            let code = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            for m in quoted.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                let key = String(code[Range(m.range(at: 1), in: code)!])
                seen += 1
                try expect(Words.has(key), "\(file): words.json lacks \(key)")
            }
        }
        try expect(seen >= 30, "the scan found only \(seen) keys")
    }),
]
