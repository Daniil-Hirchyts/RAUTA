import Testing
@testable import Rauta

/// The VoiceOver "Move up" / "Move down" actions on reorderable rows.
@Suite("Reorder operations")
struct ReorderingTests {
    private let all: Set<String> = ["a", "b", "c", "d"]

    @Test func movesDownPastTheNextRow() {
        #expect(["a", "b", "c"].movingElement("a", by: 1, visible: all) == ["b", "a", "c"])
    }

    @Test func movesUpPastThePreviousRow() {
        #expect(["a", "b", "c"].movingElement("c", by: -1, visible: all) == ["a", "c", "b"])
    }

    @Test func staysPutAtEitherEnd() {
        #expect(["a", "b"].movingElement("a", by: -1, visible: all) == ["a", "b"])
        #expect(["a", "b"].movingElement("b", by: 1, visible: all) == ["a", "b"])
    }

    @Test func stepsOverIdsWithoutARow() {
        // "x" is not in the catalogue, so there is no row for it to swap with.
        #expect(["a", "x", "b"].movingElement("a", by: 1, visible: all) == ["x", "b", "a"])
        #expect(["a", "x", "b"].movingElement("b", by: -1, visible: all) == ["b", "a", "x"])
    }

    @Test func ignoresUnknownIdsAndZeroOffsets() {
        #expect(["a", "b"].movingElement("z", by: 1, visible: all) == ["a", "b"])
        #expect(["a", "b"].movingElement("a", by: 0, visible: all) == ["a", "b"])
    }

    @Test func repeatedMovesKeepEveryId() {
        var ids = ["a", "b", "c", "d"]
        for _ in 0..<5 { ids = ids.movingElement("a", by: 1, visible: all) }
        #expect(ids == ["b", "c", "d", "a"])
        #expect(Set(ids) == all)
    }
}
