import Foundation

/// One action item pulled out of a dictation, before it becomes a reminder.
struct ExtractedTask: Equatable, Hashable, Identifiable {
    let id = UUID()
    var title: String
    var notes: String?
    var dueDate: Date?

    // Identity is the content, not the synthesised id: two runs producing the
    // same task are the same task, and `.task(id:)` in the popup depends on that
    // to tell a genuinely new outcome from a redraw of the current one.
    static func == (lhs: ExtractedTask, rhs: ExtractedTask) -> Bool {
        lhs.title == rhs.title && lhs.notes == rhs.notes && lhs.dueDate == rhs.dueDate
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(notes)
        hasher.combine(dueDate)
    }
}

/// Turns what the model said into tasks.
///
/// Models are asked for a bare JSON array and mostly comply, but "mostly" is not
/// a contract: they wrap it in code fences, prepend "Here are the tasks:", or
/// return a lone object instead of an array. Parsing is therefore forgiving
/// about the packaging and strict about the contents — anything that isn't a
/// usable task is dropped rather than guessed at, because the result is written
/// into the user's own reminders list.
enum TaskExtraction {
    /// Beyond this, something has gone wrong — a model looping, or a transcript
    /// being read as a list of instructions. Filing 200 reminders is far worse
    /// than filing none, so the run is abandoned rather than truncated.
    static let plausibleMaximum = 25

    static func parse(_ response: String, now: Date) -> [ExtractedTask] {
        guard let array = jsonArray(in: response) else { return [] }
        guard array.count <= plausibleMaximum else { return [] }

        return array.compactMap { element -> ExtractedTask? in
            guard let object = element as? [String: Any] else { return nil }

            let title = string(object["title"])
            guard let title, !title.isEmpty else { return nil }

            return ExtractedTask(
                title: title,
                notes: string(object["notes"]),
                dueDate: date(from: string(object["due"]), now: now)
            )
        }
    }

    // MARK: - Unwrapping

    /// Finds the array inside whatever the model wrapped it in. Slicing from the
    /// first `[` to the last `]` survives both prose either side and code fences,
    /// which a stricter parser would reject outright.
    private static func jsonArray(in response: String) -> [Any]? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "["),
              let end = trimmed.lastIndex(of: "]"),
              start < end
        else {
            // A single object instead of an array is the other common deviation.
            if let object = jsonObject(in: trimmed) { return [object] }
            return nil
        }

        let slice = String(trimmed[start...end])
        guard let data = slice.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return nil }
        return array
    }

    private static func jsonObject(in text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end,
              let data = String(text[start...end]).data(using: .utf8)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - Fields

    /// JSON null arrives as `NSNull`, and models sometimes send the string
    /// "null" instead. Both mean absent.
    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "null" else { return nil }
        return trimmed
    }

    /// Accepts the two shapes the prompt asks for, and nothing else. A date that
    /// won't parse becomes no date at all: a reminder that arrives undated is a
    /// small annoyance, one that fires at the wrong time is a real one.
    private static func date(from value: String?, now: Date) -> Date? {
        guard let value else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.timeZone = TimeZone.current
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in ["yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: value) else { continue }
            // A model that resolves "Friday" against the wrong year produces a
            // reminder buried in the past where the user will never see it.
            guard parsed > now.addingTimeInterval(-86_400) else { return nil }
            return parsed
        }
        return nil
    }
}
