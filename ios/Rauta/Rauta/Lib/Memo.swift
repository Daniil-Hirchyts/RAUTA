import Foundation

/// Remembers the last answer to an expensive question until it is asked with
/// different inputs.
///
/// Meant for `@State`: as a reference, filling it never triggers a redraw — it
/// only spares the next render the same work. A screen that reads a derived
/// list in several places per render, and once per cell while scrolling, then
/// pays for it once per change of what it is derived from.
final class Memo<Key: Equatable, Value> {
    private var key: Key?
    private var value: Value?

    func callAsFunction(_ key: Key, _ compute: () -> Value) -> Value {
        if let value, self.key == key { return value }
        let computed = compute()
        self.key = key
        value = computed
        return computed
    }
}
