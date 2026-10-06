import Foundation

/// Local calendar dates as "YYYY-MM-DD", with no time-of-day or timezone
/// shifting — the shape every workout is filed under.
///
/// The string is always a Gregorian date, whatever calendar the phone shows:
/// read with a Buddhist or Japanese calendar, "2026-10-05" would land in
/// another era. The time zone follows the phone's as it changes, so crossing
/// one while the app runs moves "today" with it.
enum CalendarDate {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }()

    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func toISO(_ date: Date) -> String { isoFormatter.string(from: date) }

    static func parse(_ iso: String) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 0, parts[1] > 0, parts[2] > 0 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }

    static func shift(_ iso: String, by days: Int) -> String {
        guard let date = parse(iso), let shifted = calendar.date(byAdding: .day, value: days, to: date)
        else { return iso }
        return toISO(shifted)
    }

    /// One formatter per template and locale. Building a `DateFormatter` costs
    /// far more than using one, and date labels are drawn on every row of every
    /// list.
    private static let formatters: NSCache<NSString, DateFormatter> = {
        let cache = NSCache<NSString, DateFormatter>()
        cache.countLimit = 32
        return cache
    }()

    /// `date` in the current locale's own rendering of `template` ("MMMM",
    /// "EEEMMMd"…).
    static func string(from date: Date, template: String) -> String {
        let locale = Locale.current
        let key = "\(locale.identifier)|\(template)" as NSString
        let formatter: DateFormatter
        if let cached = formatters.object(forKey: key) {
            formatter = cached
        } else {
            formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate(template)
            formatters.setObject(formatter, forKey: key)
        }
        return formatter.string(from: date)
    }

    static func format(_ iso: String, _ template: String) -> String {
        guard let date = parse(iso) else { return iso }
        return string(from: date, template: template)
    }

    static func short(_ iso: String) -> String { format(iso, "EEEMMMd") }
    static func long(_ iso: String) -> String { format(iso, "EEEEMMMMd") }
    static func weekdayShort(_ iso: String) -> String { format(iso, "EEE") }
    static func monthShort(_ iso: String) -> String { format(iso, "MMM") }
    /// The day of the month on its own, for a date stamp that shows the weekday
    /// above it and the month below.
    static func dayOfMonth(_ iso: String) -> String { format(iso, "d") }

    static var today: String { toISO(Date()) }
}
