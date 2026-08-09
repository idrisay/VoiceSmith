import EventKit
import Foundation

/// Writes events into Apple Calendar.
///
/// Separate from `RemindersService` because the permissions are separate — macOS
/// asks for calendars and reminders independently, and someone may well grant
/// one and refuse the other — but sharing its `EKEventStore`.
@MainActor
final class CalendarService {
    static let shared = CalendarService()

    private var store: EKEventStore { EventKitStore.shared }

    private init() {}

    // MARK: - Permission

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    var hasBeenAsked: Bool {
        EKEventStore.authorizationStatus(for: .event) != .notDetermined
    }

    @discardableResult
    func requestAccess() async -> Bool {
        // Write-only access exists for calendars and would be enough to add an
        // event — but not to show the user which calendar it landed in, or to
        // take it back. Undo is worth the fuller prompt.
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    // MARK: - Calendars

    func availableCalendars() -> [(id: String, title: String)] {
        store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { (id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func destination(_ preferredID: String) -> EKCalendar? {
        if !preferredID.isEmpty,
           let chosen = store.calendar(withIdentifier: preferredID),
           chosen.allowsContentModifications {
            return chosen
        }
        return store.defaultCalendarForNewEvents
    }

    func calendarTitle(forID id: String) -> String? {
        destination(id).map(\.title)
    }

    // MARK: - Writing

    /// Adds one event, returning the identifier needed to take it back.
    func save(_ action: DetectedAction, toCalendarWithID calendarID: String) throws -> String {
        guard isAuthorized else { throw VoiceSmithError.calendarPermissionDenied }
        guard let calendar = destination(calendarID) else {
            throw VoiceSmithError.calendarUnavailable(
                detail: "there is no writable calendar"
            )
        }
        guard let start = action.start else {
            throw VoiceSmithError.calendarUnavailable(detail: "no date was given")
        }

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = action.title
        event.notes = action.notes
        event.startDate = start
        event.isAllDay = action.isAllDay

        // An hour is the honest default for "lunch with Sam at one" — the
        // speaker gave a start and nothing else, and a zero-length event is
        // invalid. All-day events run to the end of that day instead.
        event.endDate = action.end
            ?? (action.isAllDay
                ? Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
                : start.addingTimeInterval(3600))

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            store.reset()
            throw VoiceSmithError.calendarUnavailable(detail: error.localizedDescription)
        }
        return event.eventIdentifier
    }

    /// Undo. Best-effort, for the same reason as Reminders: an event the user
    /// has since edited is theirs, and failing to remove it isn't worth an error
    /// on top of an action they asked to reverse.
    func remove(identifier: String) {
        guard let event = store.event(withIdentifier: identifier) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }
}
