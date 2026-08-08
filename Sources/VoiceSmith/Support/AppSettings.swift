import Foundation
import Combine

/// UserDefaults-backed preferences. Deliberately holds no secrets — those are in ``Keychain``.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var speechProvider: SpeechProviderKind {
        didSet { defaults.set(speechProvider.rawValue, forKey: "speechProvider") }
    }
    @Published var speechModel: String {
        didSet { defaults.set(speechModel, forKey: "speechModel") }
    }
    @Published var textProvider: TextProviderKind {
        didSet { defaults.set(textProvider.rawValue, forKey: "textProvider") }
    }
    @Published var textModel: String {
        didSet { defaults.set(textModel, forKey: "textModel") }
    }
    @Published var modeID: String {
        didSet { defaults.set(modeID, forKey: "modeID") }
    }
    @Published var language: String {
        didSet { defaults.set(language, forKey: "language") }
    }

    // Delivery — each step is independently switchable, per the spec.
    @Published var copyToClipboard: Bool {
        didSet { defaults.set(copyToClipboard, forKey: "copyToClipboard") }
    }
    @Published var autoPaste: Bool {
        didSet { defaults.set(autoPaste, forKey: "autoPaste") }
    }
    @Published var showNotification: Bool {
        didSet { defaults.set(showNotification, forKey: "showNotification") }
    }
    @Published var improveAutomatically: Bool {
        didSet { defaults.set(improveAutomatically, forKey: "improveAutomatically") }
    }
    /// Off by default. It costs a second model call and writes to a list the
    /// user owns, so it is opted into rather than out of.
    /// Double-tap Option captures straight to the to-do list. On by default:
    /// it costs nothing until used, and it is the only route to the feature
    /// that needs no menu bar icon to find.
    @Published var triggerTodoOnDoubleOption: Bool {
        didSet { defaults.set(triggerTodoOnDoubleOption, forKey: "triggerTodoOnDoubleOption") }
    }
    @Published var addToTaskList: Bool {
        didSet { defaults.set(addToTaskList, forKey: "addToTaskList") }
    }
    /// Empty means whichever list Reminders itself treats as the default.
    @Published var reminderListID: String {
        didSet { defaults.set(reminderListID, forKey: "reminderListID") }
    }

    @Published var audioRetention: AudioRetention {
        didSet { defaults.set(audioRetention.rawValue, forKey: "audioRetention") }
    }
    @Published var maxRecordingSeconds: Int {
        didSet { defaults.set(maxRecordingSeconds, forKey: "maxRecordingSeconds") }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }
    @Published var customModes: [ImprovementMode] {
        didSet {
            if let data = try? JSONEncoder().encode(customModes) {
                defaults.set(data, forKey: "customModes")
            }
        }
    }
    /// Double-tap Shift as the primary trigger. Needs Accessibility, since a
    /// modifier-only tap can't be a system hot key.
    @Published var triggerOnDoubleShift: Bool {
        didSet { defaults.set(triggerOnDoubleShift, forKey: "triggerOnDoubleShift") }
    }
    @Published var shortcutKeyCode: UInt32 {
        didSet { defaults.set(Int(shortcutKeyCode), forKey: "shortcutKeyCode") }
    }
    @Published var shortcutModifiers: UInt32 {
        didSet { defaults.set(Int(shortcutModifiers), forKey: "shortcutModifiers") }
    }

    private init() {
        defaults.register(defaults: [
            "speechProvider": SpeechProviderKind.appleSpeech.rawValue,
            "speechModel": SpeechProviderKind.appleSpeech.defaultModel,
            "textProvider": TextProviderKind.anthropic.rawValue,
            "textModel": TextProviderKind.anthropic.defaultModel,
            "modeID": "professional",
            "language": "auto",
            "addToTaskList": false,
            "triggerTodoOnDoubleOption": true,
            "reminderListID": "",
            "copyToClipboard": true,
            "autoPaste": true,
            "showNotification": true,
            "improveAutomatically": true,
            "audioRetention": AudioRetention.deleteAfterTranscription.rawValue,
            "maxRecordingSeconds": 600,
            "hasCompletedOnboarding": false,
            "triggerOnDoubleShift": true,
            // ⌃⌥⌘Space. kVK_Space is 49; 6400 = controlKey|optionKey|cmdKey.
            // Not ⌥⌘Space: macOS reserves that for "Show Finder search window",
            // so it opened Finder instead of recording.
            "shortcutKeyCode": 49,
            "shortcutModifiers": 6400,
        ])

        speechProvider = SpeechProviderKind(rawValue: defaults.string(forKey: "speechProvider") ?? "") ?? .appleSpeech
        speechModel = defaults.string(forKey: "speechModel") ?? SpeechProviderKind.appleSpeech.defaultModel
        textProvider = TextProviderKind(rawValue: defaults.string(forKey: "textProvider") ?? "") ?? .anthropic
        textModel = defaults.string(forKey: "textModel") ?? TextProviderKind.anthropic.defaultModel
        modeID = defaults.string(forKey: "modeID") ?? "professional"
        language = defaults.string(forKey: "language") ?? "auto"
        addToTaskList = defaults.bool(forKey: "addToTaskList")
        triggerTodoOnDoubleOption = defaults.bool(forKey: "triggerTodoOnDoubleOption")
        reminderListID = defaults.string(forKey: "reminderListID") ?? ""
        copyToClipboard = defaults.bool(forKey: "copyToClipboard")
        autoPaste = defaults.bool(forKey: "autoPaste")
        showNotification = defaults.bool(forKey: "showNotification")
        improveAutomatically = defaults.bool(forKey: "improveAutomatically")
        audioRetention = AudioRetention(rawValue: defaults.string(forKey: "audioRetention") ?? "") ?? .deleteAfterTranscription
        maxRecordingSeconds = defaults.integer(forKey: "maxRecordingSeconds")
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        triggerOnDoubleShift = defaults.bool(forKey: "triggerOnDoubleShift")
        shortcutKeyCode = UInt32(defaults.integer(forKey: "shortcutKeyCode"))
        shortcutModifiers = UInt32(defaults.integer(forKey: "shortcutModifiers"))

        if let data = defaults.data(forKey: "customModes"),
           let decoded = try? JSONDecoder().decode([ImprovementMode].self, from: data) {
            customModes = decoded
        } else {
            customModes = []
        }
    }

    var allModes: [ImprovementMode] { ImprovementMode.builtIns + customModes }

    var activeMode: ImprovementMode {
        allModes.first { $0.id == modeID } ?? ImprovementMode.builtIns[0]
    }

    /// True when the current pipeline never sends audio or text off the machine.
    var isFullyLocal: Bool {
        speechProvider.isLocal && (!improveAutomatically || textProvider.isLocal)
    }
}
