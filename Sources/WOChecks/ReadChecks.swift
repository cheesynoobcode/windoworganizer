import Foundation
import WindowOrganizerCore

/// Lets the main run loop (timers, main-actor tasks) run until `done` holds or `seconds` pass.
private func pump(_ seconds: Double = 5, until done: () -> Bool) {
    let end = Date().addingTimeInterval(seconds)
    while !done() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
}

private final class ReadWorld: @unchecked Sendable {
    var context = "desktop 1"
    var reads = 0
    var outcomes: [String] = []
}

private func describe(_ o: ReadOutcome<String, Int>) -> String {
    switch o { case .listing(let v, let c): return "listing \(v) @ \(c)"; case .contextChanged: return "changed" }
}

let readChecks: [(String, @Sendable () throws -> Void)] = [
    ("a slow window read leaves the main loop running and delivers the listing", {
        let w = ReadWorld()
        MainActor.assumeIsolated {
            let reader = ReadCoordinator<String, Int>(context: { w.context }, read: { _ in w.reads += 1; try? await Task.sleep(nanoseconds: 300_000_000); return 7 })
            var ticks = 0
            let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in ticks += 1 }
            reader.request { w.outcomes.append(describe($0)) }
            try? expect(reader.isReading, "the read must be running after the request")
            pump { !w.outcomes.isEmpty }
            timer.invalidate()
            try? expect(ticks >= 5, "main-loop timer ticked only \(ticks) times during a 0.3 s read")
        }
        try expectEqual(w.outcomes, ["listing 7 @ desktop 1"])
    }),
    ("a desktop switch during the read discards the listing", {
        let w = ReadWorld()
        MainActor.assumeIsolated {
            let reader = ReadCoordinator<String, Int>(context: { w.context }, read: { _ in try? await Task.sleep(nanoseconds: 100_000_000); w.context = "desktop 2"; return 7 })
            reader.request { w.outcomes.append(describe($0)) }
            pump { !w.outcomes.isEmpty }
        }
        try expectEqual(w.outcomes, ["changed"])
    }),
    ("two quick requests share one read", {
        let w = ReadWorld()
        MainActor.assumeIsolated {
            let reader = ReadCoordinator<String, Int>(context: { w.context }, read: { _ in w.reads += 1; try? await Task.sleep(nanoseconds: 100_000_000); return 3 })
            reader.request { w.outcomes.append("a " + describe($0)) }
            reader.request { w.outcomes.append("b " + describe($0)) }
            pump { w.outcomes.count == 2 }
        }
        try expectEqual(w.reads, 1)
        try expectEqual(w.outcomes, ["a listing 3 @ desktop 1", "b listing 3 @ desktop 1"])
    }),
    ("a request that joins after the desktop changed gets no listing", {
        let w = ReadWorld()
        MainActor.assumeIsolated {
            let reader = ReadCoordinator<String, Int>(context: { w.context }, read: { _ in try? await Task.sleep(nanoseconds: 150_000_000); return 3 })
            reader.request { w.outcomes.append("a " + describe($0)) }
            w.context = "desktop 2"
            reader.request { w.outcomes.append("b " + describe($0)) }
            pump { w.outcomes.count == 2 }
        }
        try expectEqual(w.outcomes, ["a changed", "b changed"])
    }),
    ("a request after a finished read starts a new read", {
        let w = ReadWorld()
        MainActor.assumeIsolated {
            let reader = ReadCoordinator<String, Int>(context: { w.context }, read: { _ in w.reads += 1; return w.reads })
            reader.request { w.outcomes.append(describe($0)) }
            pump { w.outcomes.count == 1 }
            try? expect(!reader.isReading, "no read may be running after delivery")
            reader.request { w.outcomes.append(describe($0)) }
            pump { w.outcomes.count == 2 }
        }
        try expectEqual(w.outcomes, ["listing 1 @ desktop 1", "listing 2 @ desktop 1"])
    }),
]
