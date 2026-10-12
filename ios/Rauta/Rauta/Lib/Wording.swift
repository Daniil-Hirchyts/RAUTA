import Foundation

enum Wording {
    static func titleCase(_ value: String) -> String {
        var result = ""
        var atWordStart = true
        for character in value {
            if character.isLetter || character.isNumber {
                result.append(atWordStart ? Character(character.uppercased()) : character)
                atWordStart = false
            } else {
                result.append(character)
                atWordStart = true
            }
        }
        return result
    }

    /// "1 workout", "3 workouts". The app counts things in a lot of places and
    /// they should all read the same way.
    static func countLabel(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    /// "a", "a and b", "a, b and c".
    static func list(_ items: [String], conjunction: String = "and") -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        return items.dropLast().joined(separator: ", ") + " \(conjunction) " + last
    }
}
