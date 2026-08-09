import Foundation

/// Something the user said that could become an entry somewhere.
struct DetectedAction: Equatable, Hashable {
    enum Kind: String {
        case event, reminder
    }

    /// The classifier's best guess. Only a default for which button is
    /// highlighted — the user can send it anywhere, because "remind me to book
    /// the room" and "schedule the room booking" are genuinely the same thought.
    var kind: Kind
    var title: String
    var notes: String?
    /// Events always have one. Reminders may not.
    var start: Date?
    var end: Date?
    /// A date with no time of day: an all-day event, or an undated reminder.
    var isAllDay: Bool

    var asTask: ExtractedTask {
        ExtractedTask(title: title, notes: notes, dueDate: start)
    }
}

/// Reads the classifier's reply.
///
/// Same posture as `TaskExtraction`: forgiving about how the JSON is wrapped,
/// unforgiving about its contents. Nothing here is written anywhere without the
/// user pressing a button first, so the cost of a bad parse is a nonsense offer
/// rather than a nonsense calendar entry — but a nonsense offer trains people to
/// ignore the feature, which is nearly as bad.
enum ActionDetection {
    static func parse(_ response: String, now: Date) -> DetectedAction? {
        guard let object = jsonObject(in: response) else { return nil }

        guard let rawKind = string(object["kind"]),
              let kind = DetectedAction.Kind(rawValue: rawKind.lowercased())
        else { return nil }   // "none" lands here too, which is the point.

        guard let title = string(object["title"]), !title.isEmpty else { return nil }

        let start = date(from: string(object["start"]), now: now)
        let end = date(from: string(object["end"]), now: now)

        // An event with no time is not an event we can offer honestly.
        if kind == .event, start == nil { return nil }

        return DetectedAction(
            kind: kind,
            title: title,
            notes: string(object["notes"]),
            start: start,
            end: end.flatMap { e in start.map { e > $0 ? e : $0.addingTimeInterval(3600) } },
            isAllDay: start.map { isMidnight($0) } ?? true
        )
    }

    private static func isMidnight(_ date: Date) -> Bool {
        Calendar.current.isDate(
            date, equalTo: Calendar.current.startOfDay(for: date), toGranularity: .minute
        )
    }

    private static func jsonObject(in text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}"),
              start < end,
              let data = String(trimmed[start...end]).data(using: .utf8)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "null" else { return nil }
        return trimmed
    }

    private static func date(from value: String?, now: Date) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: value) else { continue }
            // A meeting booked into last year is worse than an undated offer.
            guard parsed > now.addingTimeInterval(-86_400) else { return nil }
            return parsed
        }
        return nil
    }
}
