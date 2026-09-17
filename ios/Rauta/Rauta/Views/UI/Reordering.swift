import SwiftUI

extension Array where Element == String {
    /// Moves `id` one place up (`offset < 0`) or down past the neighbouring id
    /// in `visible` — the move a VoiceOver "Move up" / "Move down" action asks
    /// for. Ids with no row of their own are stepped over and keep their order.
    /// Unchanged when `id` is missing or already at that end.
    func movingElement(_ id: String, by offset: Int, visible: Set<String>) -> [String] {
        guard offset != 0, let from = firstIndex(of: id) else { return self }
        let step = offset > 0 ? 1 : -1
        var target = from + step
        while indices.contains(target), !visible.contains(self[target]) { target += step }
        guard indices.contains(target) else { return self }
        var next = self
        next.remove(at: from)
        // Down: the neighbour slid up into `target - 1`, so `target` is after it.
        // Up: the neighbour is still at `target`, so inserting there is before it.
        next.insert(id, at: target)
        return next
    }


    /// Replays a `reorderContainer` difference onto an array of exercise ids.
    ///
    /// The system reports where the lifted rows landed rather than an index
    /// pair, so the ids come out first and go back in ahead of the anchor —
    /// which keeps the order the person picked them up in. Ids with no entry in
    /// the catalogue have no row to lift, so they simply keep their place.
    func applyingReorder<CollectionID>(
        _ difference: ReorderDifference<String, CollectionID>
    ) -> [String] {
        let moving = difference.sources
        guard !moving.isEmpty else { return self }
        let lifted = Set(moving)
        var next = filter { !lifted.contains($0) }
        switch difference.destination.position {
        case .before(let anchor):
            // An anchor that was itself lifted is no longer in `next`; dropping
            // at the end is the only sensible reading of that.
            next.insert(contentsOf: moving, at: next.firstIndex(of: anchor) ?? next.endIndex)
        case .end:
            next.append(contentsOf: moving)
        }
        return next
    }
}
