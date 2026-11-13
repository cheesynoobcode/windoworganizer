import Foundation

public enum ReadOutcome<Context: Sendable, Value: Sendable>: Sendable {
    case listing(Value, Context)
    case contextChanged
}

/// One window read at a time, off the main actor (GPT-WO-S5). A request made while a read runs joins it. The context
/// (screens + desktop) is compared again after the read: a request gets the listing only if it is the same at its own
/// start, at the read's start and at the end, so nothing is planned or saved from a read that crossed a desktop switch.
@MainActor
public final class ReadCoordinator<Context: Equatable & Sendable, Value: Sendable> {
    public typealias Done = @MainActor (ReadOutcome<Context, Value>) -> Void
    private let context: @MainActor () -> Context
    private let read: @Sendable (Context) async -> Value
    private var waiters: [(before: Context, done: Done)] = []
    private var startContext: Context?
    public private(set) var isReading = false

    public init(context: @escaping @MainActor () -> Context, read: @escaping @Sendable (Context) async -> Value) {
        self.context = context; self.read = read
    }

    public func request(_ done: @escaping Done) {
        waiters.append((context(), done))
        guard !isReading else { return }
        let start = context()
        isReading = true; startContext = start
        let read = self.read
        Task {
            let value = await Task.detached { await read(start) }.value
            self.finish(value)
        }
    }

    private func finish(_ value: Value) {
        let after = context(), start = startContext
        let batch = waiters
        waiters = []; startContext = nil; isReading = false
        for (before, done) in batch { done(before == after && start == after ? .listing(value, after) : .contextChanged) }
    }
}
