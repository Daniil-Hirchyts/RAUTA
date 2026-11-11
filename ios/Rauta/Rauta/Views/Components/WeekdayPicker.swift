import SwiftUI

/// Monday to Sunday as seven toggles, in the person's own weekday names.
struct WeekdayPicker: View {
    @Binding var days: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    Haptics.trigger(.selection)
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(Self.shortName(day))
                        .font(Theme.sans(13, weight: .bold))
                        .foregroundStyle(on ? Theme.primaryForeground : Theme.foreground)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(on ? Theme.primary : Theme.muted.opacity(0.4))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.fullName(day))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    /// ISO weekday 1 = Monday.
    static func shortName(_ day: Int) -> String {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return symbols[day % 7]
    }

    static func fullName(_ day: Int) -> String {
        Calendar.current.standaloneWeekdaySymbols[day % 7]
    }
}
