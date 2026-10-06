import Foundation

/// Facts about the process the app is running in.
nonisolated enum AppEnvironment {
    /// True while the app is only the host for its unit tests.
    ///
    /// The tests drive the stores directly. The services that reach outside the
    /// app — iCloud, the calendar, reminders, Health, the watch, the Lock
    /// Screen, notifications, sound — must not act on what they do: a test that
    /// empties the library would otherwise upload that empty library to the
    /// person's iCloud, from where their other devices pull it.
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }()
}
