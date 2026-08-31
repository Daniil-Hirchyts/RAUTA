import Foundation

/// The one place the app and the widget extension agree on: a container both
/// can reach, holding the prepared exercise frames the Live Activity renders.
///
/// An activity's content state has a hard size limit and cannot carry an
/// image, so the app writes a PNG here and sends only its file name.
enum WorkoutActivityStore {
    static let appGroupIdentifier = "group.com.hirchyts.gymlib"

    /// `nil` when the App Group is unavailable — an entitlement that failed to
    /// provision, for instance. Every caller degrades to a card without a
    /// thumbnail rather than failing.
    static var framesDirectory: URL? {
        guard
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            )
        else { return nil }

        let directory = container.appendingPathComponent("ExerciseFrames", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    static func frameURL(named name: String) -> URL? {
        guard !name.isEmpty, let directory = framesDirectory else { return nil }
        return directory.appendingPathComponent(name)
    }
}
