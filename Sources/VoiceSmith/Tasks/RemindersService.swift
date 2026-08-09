import EventKit
import Foundation

/// Writes tasks into Apple Reminders.
///
/// Reminders rather than a list of our own: the point of dictating a task is to
/// put it where you already look for tasks. A list inside VoiceSmith would be a
/// second inbox, and second inboxes don't get read. This one reaches the user's
/// phone, their watch, Siri, and the widget, none of which we would ever build.
@MainActor
final class RemindersService {
    static let shared = RemindersService()

    private var store: EKEventStore { EventKitStore.shared }

    private init() {}

    // MARK: - Permission

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    /// True once macOS has been asked, whatever the answer. Used to tell "never
    /// offered" apart from "offered and declined", which need different prompts.
    var hasBeenAsked: Bool {
        EKEventStore.authorizationStatus(for: .reminder) != .notDetermined
    }

    @discardableResult
    func requestAccess() async -> Bool {
        // Only full access can write. macOS 14 replaced the old blanket
        // `.authorized` with this, and the write-only variant covers events, not
        // reminders — so there is no lesser grant to fall back on.
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    // MARK: - Lists

    /// Every reminders list the user has, for the Settings picker.
    func availableLists() -> [(id: String, title: String)] {
        store.calendars(for: .reminder)
            .filter { $0.allowsContentModifications }
            .map { (id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// The list tasks go to. An empty stored id means "whatever Reminders itself
    /// defaults to", which is the right behaviour until the user says otherwise
    /// — and the right fallback if the list they chose is later deleted.
    private func destination(_ preferredID: String) -> EKCalendar? {
        if !preferredID.isEmpty,
           let chosen = store.calendar(withIdentifier: preferredID),
           chosen.allowsContentModifications {
            return chosen
        }
        return store.defaultCalendarForNewReminders()
    }

    func listTitle(forID id: String) -> String? {
        destination(id).map(\.title)
    }

    // MARK: - Writing

    /// Saves every task, returning the identifiers needed to take them back.
    ///
    /// Committed as one batch: a half-written set of reminders is worse than
    /// none, because the user can't tell which half.
    func save(_ tasks: [ExtractedTask], toListWithID listID: String) throws -> [String] {
        guard isAuthorized else { throw VoiceSmithError.remindersPermissionDenied }
        guard let calendar = destination(listID) else {
            throw VoiceSmithError.remindersUnavailable(
                detail: "there is no writable list in Reminders"
            )
        }

        var identifiers: [String] = []
        for task in tasks {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar
            reminder.title = task.title
            reminder.notes = task.notes

            if let due = task.dueDate {
                // Date-only tasks get no alarm; a task with a stated time gets
                // one, because that is what saying a time meant.
                let hasTime = !Calendar.current.isDate(
                    due, equalTo: Calendar.current.startOfDay(for: due), toGranularity: .minute
                )
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    hasTime
                        ? [.year, .month, .day, .hour, .minute]
                        : [.year, .month, .day],
                    from: due
                )
                if hasTime {
                    reminder.addAlarm(EKAlarm(absoluteDate: due))
                }
            }

            do {
                try store.save(reminder, commit: false)
                identifiers.append(reminder.calendarItemIdentifier)
            } catch {
                store.reset()
                throw VoiceSmithError.remindersUnavailable(detail: error.localizedDescription)
            }
        }

        do {
            try store.commit()
        } catch {
            store.reset()
            throw VoiceSmithError.remindersUnavailable(detail: error.localizedDescription)
        }
        return identifiers
    }

    /// Undo. Best-effort by design: a reminder the user has already edited or
    /// ticked off is theirs now, and failing to remove one is not worth an error
    /// on top of an action they asked to reverse.
    func remove(identifiers: [String]) {
        for id in identifiers {
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { continue }
            try? store.remove(reminder, commit: false)
        }
        try? store.commit()
    }
}
