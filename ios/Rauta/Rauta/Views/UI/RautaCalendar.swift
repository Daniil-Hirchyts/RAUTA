import SwiftUI

/// The app's one calendar: a month on a warm card, today onwards, with the
/// chosen days filled in the accent.
///
/// Planning a week picks several days on it; moving or creating a workout picks
/// one. Both are the same month on the same card, so a date reads the same
/// wherever it is asked for.
struct RautaCalendar: View {
    enum Selection {
        /// Any number of days, as ISO dates.
        case multiple(Binding<Set<String>>)
        /// Exactly one day. Tapping another day moves it; tapping the chosen
        /// day keeps it.
        case single(Binding<String>)
    }

    let selection: Selection
    var label = "Dates"
    var onChange: () -> Void = {}

    private var calendar: Calendar { Calendar.current }
    private var earliestDate: Date { calendar.startOfDay(for: Date()) }

    private var chosen: Set<String> {
        switch selection {
        case .multiple(let dates): return dates.wrappedValue
        case .single(let date): return [date.wrappedValue]
        }
    }

    private var components: Binding<Set<DateComponents>> {
        Binding(
            get: {
                Set(chosen.compactMap { iso in
                    guard let date = CalendarDate.parse(iso) else { return nil }
                    return calendar.dateComponents([.year, .month, .day], from: date)
                })
            },
            set: { values in
                let picked = Set(values.compactMap { components -> String? in
                    guard let date = calendar.date(from: components) else { return nil }
                    let iso = CalendarDate.toISO(date)
                    return iso >= CalendarDate.today ? iso : nil
                })
                switch selection {
                case .multiple(let dates):
                    guard picked != dates.wrappedValue else { return }
                    dates.wrappedValue = picked
                case .single(let date):
                    // The day just tapped is the one not chosen before; an
                    // emptied selection is the chosen day tapped again, which
                    // keeps it and still counts as choosing it.
                    if let next = picked.subtracting([date.wrappedValue]).first {
                        date.wrappedValue = next
                    }
                }
                Haptics.trigger(.selection)
                onChange()
            }
        )
    }

    var body: some View {
        MultiDatePicker(label, selection: components, in: earliestDate...)
            .labelsHidden()
            .tint(Theme.primary)
            // A month, not a stretched grid, whatever room it is offered.
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background { GradientCard(radius: Theme.Radius.xl3, accent: Theme.primary, strength: 0.7) }
    }
}
