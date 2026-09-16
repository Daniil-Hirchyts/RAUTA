import SwiftUI

extension Array where Element == String {
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
