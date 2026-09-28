import Foundation
import Testing
@testable import Rauta

@MainActor
@Suite("Coalesced work")
struct CoalescedWorkTests {
    @Test func requestsDuringARunFoldIntoOneMoreRun() async {
        var runs = 0
        var gate: CheckedContinuation<Void, Never>?
        let work = CoalescedWork {
            runs += 1
            if runs == 1 { await withCheckedContinuation { gate = $0 } }
        }

        work.request()
        while gate == nil { await Task.yield() }
        // Five more requests while the first run is still going.
        for _ in 0..<5 { work.request() }
        gate?.resume()
        while runs < 2 { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        #expect(runs == 2)

        // Idle again: the next request starts a run of its own.
        work.request()
        while runs < 3 { await Task.yield() }
        #expect(runs == 3)
    }
}
