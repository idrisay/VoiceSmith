import EventKit
import Foundation

/// One `EKEventStore` for the process.
///
/// Reminders and Calendar are separate permissions but the same framework, and
/// EventKit caches against the store instance — a second one would re-fetch
/// everything and, worse, lose the authorisation state just established on the
/// first. Both services share this.
@MainActor
enum EventKitStore {
    static let shared = EKEventStore()
}
