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
    /// Which modifier tap captures straight to the to-do list. Option by
    /// default, and changeable — see `dictationTapModifier`.
    @Published var todoTapModifier: TapModifier {
        didSet { defaults.set(todoTapModifier.rawValue, forKey: "todoTapModifier") }
    }
    /// Offer to file an event or reminder when a dictation sounds like one.
    /// On by default: it only ever adds a button, never changes what the
    /// dictation itself does, and costs a model call only when a local phrase
    /// match already suggests it's worth one.
    @Published var offerDetectedActions: Bool {
        didSet { defaults.set(offerDetectedActions, forKey: "offerDetectedActions") }
    }
    /// Empty means whichever calendar Calendar itself treats as the default.
    @Published var calendarID: String {
        didSet { defaults.set(calendarID, forKey: "calendarID") }
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
    /// Names, product names, and jargon the speech model gets wrong.
    @Published var vocabularyTerms: [String] {
        didSet { defaults.set(vocabularyTerms, forKey: "vocabularyTerms") }
    }
    var vocabulary: Vocabulary { Vocabulary(vocabularyTerms) }

    @Published var customModes: [ImprovementMode] {
        didSet {
            if let data = try? JSONEncoder().encode(customModes) {
                defaults.set(data, forKey: "customModes")
            }
        }
    }
    /// Double-tap Shift as the primary trigger. Needs Accessibility, since a
    /// modifier-only tap can't be a system hot key.
    /// Which modifier tap starts and stops dictation. Shift by default.
    ///
    /// Suggested, not fixed. Which taps are free depends entirely on what else
    /// someone runs — JetBrains claims Shift, macOS Dictation can claim Control
    /// — so the choice belongs to the user, in onboarding or in Settings.
    @Published var dictationTapModifier: TapModifier {
        didSet { defaults.set(dictationTapModifier.rawValue, forKey: "dictationTapModifier") }
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
            "offerDetectedActions": true,
            "calendarID": "",
            "reminderListID": "",
            "copyToClipboard": true,
            "autoPaste": true,
            "showNotification": true,
            "improveAutomatically": true,
            "audioRetention": AudioRetention.deleteAfterTranscription.rawValue,
            "maxRecordingSeconds": 600,
            "hasCompletedOnboarding": false,
            // The two tap modifiers are deliberately absent: registering a
            // default puts it in the search list, so `string(forKey:)` would
            // always find one and `storedModifier` could never see that the key
            // is unset — which is how it recognises an upgrade from the old
            // boolean settings. Their defaults live in `storedModifier`'s
            // `fallback` instead.
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
        offerDetectedActions = defaults.bool(forKey: "offerDetectedActions")
        calendarID = defaults.string(forKey: "calendarID") ?? ""
        // Migration: both triggers used to be on/off booleans on a fixed
        // modifier. Anyone who had switched one off keeps it off.
        todoTapModifier = Self.storedModifier(
            defaults, key: "todoTapModifier", legacyKey: "triggerTodoOnDoubleOption", fallback: .option
        )
        reminderListID = defaults.string(forKey: "reminderListID") ?? ""
        copyToClipboard = defaults.bool(forKey: "copyToClipboard")
        autoPaste = defaults.bool(forKey: "autoPaste")
        showNotification = defaults.bool(forKey: "showNotification")
        improveAutomatically = defaults.bool(forKey: "improveAutomatically")
        audioRetention = AudioRetention(rawValue: defaults.string(forKey: "audioRetention") ?? "") ?? .deleteAfterTranscription
        maxRecordingSeconds = defaults.integer(forKey: "maxRecordingSeconds")
        hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
        dictationTapModifier = Self.storedModifier(
            defaults, key: "dictationTapModifier", legacyKey: "triggerOnDoubleShift", fallback: .shift
        )
        shortcutKeyCode = UInt32(defaults.integer(forKey: "shortcutKeyCode"))
        shortcutModifiers = UInt32(defaults.integer(forKey: "shortcutModifiers"))

        vocabularyTerms = defaults.stringArray(forKey: "vocabularyTerms") ?? []

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

    private static func storedModifier(
        _ defaults: UserDefaults,
        key: String,
        legacyKey: String,
        fallback: TapModifier
    ) -> TapModifier {
        if let raw = defaults.string(forKey: key), let stored = TapModifier(rawValue: raw) {
            return stored
        }
        // No new-style value: honour the old boolean if one was ever written.
        if defaults.object(forKey: legacyKey) != nil {
            return defaults.bool(forKey: legacyKey) ? fallback : .off
        }
        return fallback
    }

}
