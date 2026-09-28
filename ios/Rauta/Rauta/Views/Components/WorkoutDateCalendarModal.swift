import SwiftUI

/// A workout's day, asked on top of the page with the app's calendar.
///
/// Without a `confirmTitle`, choosing a day is the answer: the modal closes and
/// the workout moves. With one, the day is only chosen until the button under
/// the calendar confirms it — for creating something on that day.
struct WorkoutDateCalendarModal: View {
    var isPresented: Bool
    var confirmTitle: String? = nil
    @State private var selectedDate: String
    let onClose: () -> Void
    let onSelect: (String) -> Void

    init(
        isPresented: Bool,
        date: String,
        confirmTitle: String? = nil,
        onClose: @escaping () -> Void,
        onSelect: @escaping (String) -> Void
    ) {
        self.isPresented = isPresented
        self.confirmTitle = confirmTitle
        _selectedDate = State(initialValue: max(date, CalendarDate.today))
        self.onClose = onClose
        self.onSelect = onSelect
    }

    var body: some View {
        AppModal(
            isPresented: isPresented,
            label: confirmTitle ?? "Choose workout date",
            onClose: onClose,
            panelPadding: 6
        ) {
            VStack(spacing: 10) {
                RautaCalendar(
                    selection: .single($selectedDate),
                    label: "Workout date",
                    onChange: {
                        guard confirmTitle == nil else { return }
                        Haptics.trigger(.success)
                        onClose()
                        onSelect(selectedDate)
                    }
                )
                if let confirmTitle {
                    AppButton(confirmTitle, size: .cta, expands: true) {
                        Haptics.trigger(.success)
                        onClose()
                        onSelect(selectedDate)
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
            }
        }
    }
}
