import Combine
import EventKit
import Foundation

/// Calendar events created by RAUTA are linked to workout ids. Only linked
/// events are moved or removed when training changes.
@MainActor
final class CalendarService {
    static let shared = CalendarService()

    struct Slot {
        var start: Date
        var end: Date
    }

    private struct Link: Codable {
        var eventId: String
        var workoutDate: String
    }

    private let store = EKEventStore()
    private let linksKey = "rauta-workout-calendar-links"
    private var links: [String: Link]
    private var cancellable: AnyCancellable?

    private init() {
        links = (Storage.defaults.data(forKey: linksKey))
            .flatMap { try? JSONDecoder().decode([String: Link].self, from: $0) } ?? [:]
    }

    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async -> Bool {
        if hasAccess { return true }
        return (try? await store.requestFullAccessToEvents()) == true
    }

    func startSync() {
        guard cancellable == nil else { return }
        cancellable = WorkoutsStore.shared.changed.sink { [weak self] in
            self?.reconcile()
        }
        reconcile()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(links) {
            Storage.defaults.set(data, forKey: linksKey)
        }
    }

    private func interval(on day: String, hour: Int, minutes: Int) -> Slot? {
        guard let date = CalendarDate.parse(day),
              let start = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date),
              let end = Calendar.current.date(byAdding: .minute, value: minutes, to: start)
        else { return nil }
        return Slot(start: start, end: end)
    }

    func freeSlots(on day: String, minutes: Int) -> [Slot] {
        guard hasAccess, AgentWords.isDate(day), (20...180).contains(minutes),
              let date = CalendarDate.parse(day),
              let endDay = Calendar.current.date(byAdding: .day, value: 1, to: date)
        else { return [] }
        let predicate = store.predicateForEvents(withStart: date, end: endDay, calendars: nil)
        let busy = store.events(matching: predicate).filter { $0.availability != .free }
        return (7...21).compactMap { hour -> Slot? in
            guard let slot = interval(on: day, hour: hour, minutes: minutes),
                  slot.start > Date(), slot.end <= endDay,
                  !busy.contains(where: { $0.startDate < slot.end && $0.endDate > slot.start })
            else { return nil }
            return slot
        }
    }

    func suggestedSlot(for workout: Workout, minutes: Int) -> Slot? {
        let slots = freeSlots(on: workout.date, minutes: minutes)
        return slots.first(where: { Calendar.current.component(.hour, from: $0.start) >= 17 })
            ?? slots.first
    }

    func add(_ workout: Workout, at slot: Slot) throws -> String {
        guard hasAccess, workout.completion == nil,
              WorkoutsStore.shared.workout(workout.id) == workout,
              CalendarDate.toISO(slot.start) == workout.date,
              slot.start > Date(), slot.end > slot.start else {
            throw CalendarServiceError.stale
        }
        if let link = links[workout.id], store.event(withIdentifier: link.eventId) != nil {
            throw CalendarServiceError.alreadyLinked
        }
        guard let calendar = store.defaultCalendarForNewEvents else {
            throw CalendarServiceError.noCalendar
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = workout.name
        event.startDate = slot.start
        event.endDate = slot.end
        event.notes = "Scheduled by RAUTA for your workout."
        try store.save(event, span: .thisEvent)
        guard let id = event.eventIdentifier else { throw CalendarServiceError.noCalendar }
        links[workout.id] = Link(eventId: id, workoutDate: workout.date)
        persist()
        return id
    }

    func removeEvent(_ eventId: String) throws {
        guard hasAccess, let (workoutId, _) = links.first(where: { $0.value.eventId == eventId })
        else { throw CalendarServiceError.stale }
        if let event = store.event(withIdentifier: eventId) {
            try store.remove(event, span: .thisEvent)
        }
        links[workoutId] = nil
        persist()
    }

    func removeAllLinkedEvents() {
        guard hasAccess else { links.removeAll(); persist(); return }
        for link in links.values {
            if let event = store.event(withIdentifier: link.eventId) {
                Storage.attempt("Removing a calendar event") { try store.remove(event, span: .thisEvent) }
            }
        }
        links.removeAll()
        persist()
    }

    private func reconcile() {
        guard hasAccess, !links.isEmpty else { return }
        for (id, link) in links {
            guard let event = store.event(withIdentifier: link.eventId) else {
                links[id] = nil
                continue
            }
            guard let workout = WorkoutsStore.shared.workout(id) else {
                if Storage.attempt("Removing a calendar event", { try store.remove(event, span: .thisEvent) }) != nil {
                    links[id] = nil
                }
                continue
            }
            guard workout.date != link.workoutDate,
                  let originalDay = CalendarDate.parse(link.workoutDate),
                  let newDay = CalendarDate.parse(workout.date),
                  let newStart = Calendar.current.date(byAdding: .day,
                      value: Calendar.current.dateComponents([.day], from: originalDay, to: newDay).day ?? 0,
                      to: event.startDate),
                  let newEnd = Optional(newStart.addingTimeInterval(event.endDate.timeIntervalSince(event.startDate)))
            else { continue }
            event.startDate = newStart
            event.endDate = newEnd
            if Storage.attempt("Moving a calendar event", { try store.save(event, span: .thisEvent) }) != nil {
                links[id] = Link(eventId: event.eventIdentifier ?? link.eventId, workoutDate: workout.date)
            }
        }
        persist()
    }
}

private enum CalendarServiceError: LocalizedError {
    case stale, alreadyLinked, noCalendar
    var errorDescription: String? {
        switch self {
        case .stale: "This calendar preview is out of date. Ask for a new one."
        case .alreadyLinked: "That workout already has a RAUTA calendar event."
        case .noCalendar: "No writable calendar is available."
        }
    }
}
