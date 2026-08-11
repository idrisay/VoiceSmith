import Foundation

/// Filesystem layout. Everything lives under Application Support/VoiceSmith so
/// uninstalling means deleting one folder.
enum Storage {
    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("VoiceSmith", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var audioDirectory: URL {
        let dir = rootDirectory.appendingPathComponent("Audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var databaseURL: URL {
        rootDirectory.appendingPathComponent("notes.store")
    }

    static func newAudioURL() -> URL {
        audioDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
    }

    static func fileSize(_ url: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }

    /// Applies the retention policy. Called at launch and after each note is
    /// saved — a menu-bar app runs for weeks at a time, so a launch-only sweep
    /// would quietly turn "keep for 30 days" into "keep until you next reboot".
    static func pruneAudio(retention: AudioRetention, keeping liveURLs: Set<String>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: audioDirectory,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        for file in files {
            // Never delete a file a note still points at unless the policy says so.
            let isReferenced = liveURLs.contains(file.path)

            switch retention {
            case .deleteAfterTranscription:
                if !isReferenced { try? fm.removeItem(at: file) }
            case .keep30Days:
                let created = (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                if created < Date().addingTimeInterval(-30 * 24 * 60 * 60) {
                    try? fm.removeItem(at: file)
                }
            case .keepForever:
                continue
            }
        }
    }
}
