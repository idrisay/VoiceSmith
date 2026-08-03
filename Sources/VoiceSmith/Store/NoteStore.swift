import Foundation
import SwiftData

/// Field names are chosen so a future sync layer can add `deletedAt`, `syncedAt`,
/// and `deviceId` without migrating existing rows.
@Model
final class VoiceNote {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var duration: TimeInterval
    /// Nil once the retention policy has removed the recording.
    var audioPath: String?
    var rawTranscript: String
    var improvedText: String?
    var language: String
    var mode: String
    var speechProvider: String
    var speechModel: String
    var textProvider: String?
    var textModel: String?
    var tags: [String]
    var isFavorite: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: TimeInterval,
        audioPath: String?,
        rawTranscript: String,
        improvedText: String?,
        language: String,
        mode: String,
        speechProvider: String,
        speechModel: String,
        textProvider: String?,
        textModel: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.duration = duration
        self.audioPath = audioPath
        self.rawTranscript = rawTranscript
        self.improvedText = improvedText
        self.language = language
        self.mode = mode
        self.speechProvider = speechProvider
        self.speechModel = speechModel
        self.textProvider = textProvider
        self.textModel = textModel
        self.tags = []
        self.isFavorite = false
    }

    /// What delivery and the history list show.
    var displayText: String {
        let improved = improvedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (improved?.isEmpty == false ? improved! : rawTranscript)
    }

    var title: String {
        let firstLine = displayText
            .split(separator: "\n")
            .first
            .map(String.init) ?? displayText
        return firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : firstLine
    }
}

/// Owns the SwiftData container. A local file — no account, no server.
@MainActor
final class NoteStore: ObservableObject {
    let container: ModelContainer
    @Published private(set) var notes: [VoiceNote] = []

    init() {
        let configuration = ModelConfiguration(url: Storage.databaseURL)
        do {
            container = try ModelContainer(for: VoiceNote.self, configurations: configuration)
        } catch {
            // A corrupt store shouldn't brick the app; start over in memory and
            // let the user keep dictating.
            NSLog("VoiceSmith: could not open the note store (\(error)). Falling back to memory.")
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: VoiceNote.self, configurations: fallback)
        }
        reload()
    }

    var context: ModelContext { container.mainContext }

    func reload() {
        let descriptor = FetchDescriptor<VoiceNote>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        notes = (try? context.fetch(descriptor)) ?? []
    }

    func insert(_ note: VoiceNote) {
        context.insert(note)
        save()
    }

    func delete(_ note: VoiceNote) {
        if let path = note.audioPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        context.delete(note)
        save()
    }

    func save() {
        try? context.save()
        reload()
    }

    func touch(_ note: VoiceNote) {
        note.updatedAt = Date()
        save()
    }

    /// Case-insensitive search across both the raw and improved text, plus tags.
    func search(_ query: String) -> [VoiceNote] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return notes }
        return notes.filter { note in
            note.rawTranscript.localizedCaseInsensitiveContains(trimmed)
                || (note.improvedText ?? "").localizedCaseInsensitiveContains(trimmed)
                || note.tags.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    /// Audio paths still referenced by a note — the pruner must not delete these
    /// unless the policy explicitly says to.
    var referencedAudioPaths: Set<String> {
        Set(notes.compactMap(\.audioPath))
    }

    /// Drops audio-path references for files the retention policy removed.
    func reconcileAudioReferences() {
        var changed = false
        for note in notes {
            guard let path = note.audioPath else { continue }
            if !FileManager.default.fileExists(atPath: path) {
                note.audioPath = nil
                changed = true
            }
        }
        if changed { save() }
    }
}
