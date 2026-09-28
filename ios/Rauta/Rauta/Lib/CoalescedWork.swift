import Foundation

/// Async work that is asked for often but only needs to catch up: at most one
/// run at a time, and any requests made during a run fold into one more run
/// after it. Nothing is lost — the last request always sees a run start after
/// it — and nothing overlaps.
@MainActor
final class CoalescedWork {
    private let work: @MainActor () async -> Void
    private var running: Task<Void, Never>?
    private var pending = false

    init(_ work: @escaping @MainActor () async -> Void) {
        self.work = work
    }

    func request() {
        guard running == nil else {
            pending = true
            return
        }
        running = Task {
            repeat {
                pending = false
                await work()
            } while pending
            running = nil
        }
    }
}
