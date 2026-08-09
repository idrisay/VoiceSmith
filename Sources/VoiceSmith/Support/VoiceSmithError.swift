import Foundation

/// Every failure the spec's error table names, plus the recovery affordance for each.
/// `recoverySuggestion` is what the UI shows; `settingsAnchor` tells the UI which
/// settings pane (if any) fixes it.
enum VoiceSmithError: LocalizedError, Equatable {
    case microphonePermissionDenied
    case speechPermissionDenied
    case noInputDevice
    case inputDeviceDisconnected
    case diskFull
    case recordingFailed(String)
    case emptyRecording
    case offline(provider: String)
    case missingAPIKey(provider: String)
    case invalidAPIKey(provider: String)
    case transcriptionFailed(provider: String, detail: String)
    case improvementFailed(provider: String, detail: String)
    case localModelUnavailable(provider: String, detail: String)
    case refused(provider: String)
    case accessibilityPermissionDenied
    case remindersPermissionDenied
    case remindersUnavailable(detail: String)
    case calendarPermissionDenied
    case calendarUnavailable(detail: String)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "VoiceSmith can't access the microphone."
        case .speechPermissionDenied:
            return "VoiceSmith can't use speech recognition."
        case .noInputDevice:
            return "No microphone is available."
        case .inputDeviceDisconnected:
            return "The microphone was disconnected during recording."
        case .diskFull:
            return "There isn't enough free disk space to record."
        case .recordingFailed(let detail):
            return "Recording failed: \(detail)"
        case .emptyRecording:
            return "That recording was silent."
        case .offline(let provider):
            return "\(provider) is a cloud service and there's no network connection."
        case .missingAPIKey(let provider):
            return "No API key is set for \(provider)."
        case .invalidAPIKey(let provider):
            return "\(provider) rejected the API key."
        case .transcriptionFailed(let provider, let detail):
            return "\(provider) couldn't transcribe the audio: \(detail)"
        case .improvementFailed(let provider, let detail):
            return "\(provider) couldn't improve the text: \(detail)"
        case .localModelUnavailable(let provider, let detail):
            return "\(provider) isn't reachable: \(detail)"
        case .refused(let provider):
            return "\(provider) declined to process this text."
        case .accessibilityPermissionDenied:
            return "VoiceSmith can't paste into other apps."
        case .remindersPermissionDenied:
            return "VoiceSmith can't add to your reminders."
        case .remindersUnavailable(let detail):
            return "Reminders didn't accept the tasks: \(detail)"
        case .calendarPermissionDenied:
            return "VoiceSmith can't add to your calendar."
        case .calendarUnavailable(let detail):
            return "Calendar didn't accept the event: \(detail)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Recording requires microphone access. Open System Settings › Privacy & Security › Microphone and enable VoiceSmith."
        case .speechPermissionDenied:
            return "On-device transcription requires speech recognition access. Open System Settings › Privacy & Security › Speech Recognition, or switch to a different speech provider."
        case .noInputDevice:
            return "Connect a microphone, then try again."
        case .inputDeviceDisconnected:
            return "The audio captured so far was kept. Transcribe it, or discard it."
        case .diskFull:
            return "Free up space, or set audio retention to \"Delete after transcription\" in Settings."
        case .recordingFailed:
            return "Try again. If it keeps happening, check your input device in System Settings › Sound."
        case .emptyRecording:
            return "Nothing was discarded to a provider. Check that the right input device is selected and try again."
        case .offline:
            return "Retry when you're back online, switch to a local model, or keep the audio and transcribe it later."
        case .missingAPIKey:
            return "Add the key in Settings › Providers."
        case .invalidAPIKey:
            return "Check the key in Settings › Providers."
        case .transcriptionFailed:
            return "The audio was kept. Retry, or switch to a different speech provider."
        case .improvementFailed:
            return "The raw transcript was saved instead. Retry, or switch to a different text provider."
        case .localModelUnavailable:
            return "Make sure the local server is running and the model is installed, or switch to a cloud provider."
        case .refused:
            return "Edit the transcript, or switch to a different text provider."
        case .remindersPermissionDenied:
            return "Adding to-dos needs access to Reminders. Open System Settings › Privacy & Security › Reminders and enable VoiceSmith. Your dictation was delivered as usual."
        case .calendarPermissionDenied:
            return "Adding events needs access to Calendar. Open System Settings › Privacy & Security › Calendars and enable VoiceSmith. Your dictation was delivered as usual."
        case .calendarUnavailable:
            return "The text was delivered as usual — only the event didn't save. Check that Calendar has at least one editable calendar."
        case .remindersUnavailable:
            return "The text was delivered as usual — only the to-dos didn't file. Check that Reminders has at least one editable list."
        case .accessibilityPermissionDenied:
            return "Automatic pasting needs Accessibility access. Open System Settings › Privacy & Security › Accessibility and enable VoiceSmith. The text is still on your clipboard — press ⌘V to paste it yourself."
        }
    }

    /// Which settings tab resolves this, if any.
    var settingsAnchor: SettingsTab? {
        switch self {
        case .missingAPIKey, .invalidAPIKey, .localModelUnavailable, .offline, .refused:
            return .providers
        case .diskFull:
            return .general
        default:
            return nil
        }
    }

    /// A System Settings pane URL, when the fix lives there.
    var systemSettingsURL: URL? {
        switch self {
        case .microphonePermissionDenied:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speechPermissionDenied:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .accessibilityPermissionDenied:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .remindersPermissionDenied:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
        case .calendarPermissionDenied:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        case .noInputDevice, .inputDeviceDisconnected:
            return URL(string: "x-apple.systempreferences:com.apple.preference.sound")
        default:
            return nil
        }
    }

    /// True when retrying the same operation could plausibly succeed.
    var isRetryable: Bool {
        switch self {
        case .offline, .transcriptionFailed, .improvementFailed, .localModelUnavailable, .recordingFailed:
            return true
        default:
            return false
        }
    }
}
