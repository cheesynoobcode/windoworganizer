import Foundation
import WindowOrganizerCore

// GPT-WO-S6: a partial Restore/Apply says which windows did not move and why, and one retry touches only those.

/// A mover where some windows are gone, some do not answer, some refuse the size; the rest move.
final class PartialMover: WindowMover, @unchecked Sendable {
    var frames: [Int: Frame]
    var gone: Set<Int> = [], silent: Set<Int> = [], refuse: Set<Int> = []
    var sets: [Int] = []
    init(_ windows: [WindowInfo]) { frames = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowID, $0.frame) }) }
    func isOpen(_ id: Int) -> Bool { !gone.contains(id) }
    func frame(of id: Int) -> Frame? { gone.contains(id) || silent.contains(id) ? nil : frames[id] }
    func setFrame(_ f: Frame, of id: Int) {
        sets.append(id)
        if gone.contains(id) || silent.contains(id) { return }
        if refuse.contains(id) { return }
        frames[id] = f
    }
}

private func five() -> (windows: [WindowInfo], plan: Plan) {
    let from = Frame(x: 0, y: 0, width: 300, height: 300)
    let windows = (1...5).map { window($0, term, "T\($0)", $0, from) }
    let moves = (1...5).map { Move(windowID: $0, from: from, to: Frame(x: Double($0) * 400, y: 0, width: 300, height: 300)) }
    return (windows, Plan(moves: moves, skipped: [], unchanged: 0))
}

let partialChecks: [(String, @Sendable () throws -> Void)] = [
    ("a partial apply keeps each failed window with its reason class", {
        let (windows, plan) = five()
        let mover = PartialMover(windows)
        mover.gone = [2]; mover.silent = [4]; mover.refuse = [5]
        let r = applyPlan(plan, mover: mover)
        try expectEqual(r.placed, 2)
        try expectEqual(r.failed, 3)
        try expectEqual(r.failures.map(\.windowID), [2, 4, 5])
        try expectEqual(r.failures.map(\.reason), [.gone, .notAnswering, .refusedSize])
    }),
    ("the failure line names at most five windows, then 'and n more'", {
        let from = Frame(x: 0, y: 0, width: 300, height: 300)
        let windows = (1...7).map { window($0, term, "T\($0)", $0, from) }
        let failures = (1...7).map { FailedMove(move: Move(windowID: $0, from: from, to: from), reason: .notAnswering) }
        let line = ResultLine.notMoved(failures, in: windows)
        try expect(line.contains("T1") && line.contains("T5"), line)
        try expect(!line.contains("T6") && line.hasSuffix("and 2 more"), line)
        try expect(ResultLine.notMoved([], in: windows).isEmpty, "nothing failed, no line")
    }),
    ("retry moves only the failed windows and leaves the moved ones alone", {
        let (windows, plan) = five()
        let mover = PartialMover(windows)
        mover.silent = [3]; mover.refuse = [4]
        let first = applyPlan(plan, mover: mover)
        try expectEqual(first.failures.map(\.windowID), [3, 4])
        mover.silent = []; mover.refuse = []
        mover.sets = []
        let again = applyPlan(retryPlan(first), mover: mover)
        try expectEqual(Set(mover.sets), [3, 4])
        try expectEqual(again.placed, 2)
        try expect(again.failures.isEmpty, "both moved now")
    }),
    ("a successful apply carries no failures and no failure line", {
        let (windows, plan) = five()
        let r = applyPlan(plan, mover: PartialMover(windows))
        try expect(r.failures.isEmpty && r.failed == 0, "all five moved")
        try expect(!ResultLine.restored(r, desktop: 1, at: "10:00").contains("Not moved"), "clean line")
    }),
    ("the restore line carries the failure list when windows are given", {
        let (windows, plan) = five()
        let mover = PartialMover(windows); mover.silent = [2]
        let r = applyPlan(plan, mover: mover)
        let line = ResultLine.restored(r, failedList: ResultLine.notMoved(r.failures, in: windows), desktop: 1, at: "10:00")
        try expect(line.contains("1 could not be moved") && line.contains("T2") && line.contains("not answering"), line)
    })
]
