import Foundation

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, providers, modes, shortcuts, privacy
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .providers: return "Providers"
        case .modes: return "Modes"
        case .shortcuts: return "Shortcut"
        case .privacy: return "Privacy"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .providers: return "cpu"
        case .modes: return "wand.and.stars"
        case .shortcuts: return "keyboard"
        case .privacy: return "lock"
        }
    }
}

// MARK: - Speech providers

enum SpeechProviderKind: String, CaseIterable, Identifiable, Codable {
    case appleSpeech
    case whisperCPP
    case openAIWhisper
    case groqWhisper
    case deepgram
    case assemblyAI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSpeech: return "Apple Speech"
        case .whisperCPP: return "Whisper.cpp"
        case .openAIWhisper: return "OpenAI Whisper"
        case .groqWhisper: return "Groq Whisper"
        case .deepgram: return "Deepgram"
        case .assemblyAI: return "AssemblyAI"
        }
    }

    /// Local providers never send audio off the machine. Surfaced in the recording
    /// window so the user always knows whether the recording is leaving the device.
    var isLocal: Bool {
        switch self {
        case .appleSpeech, .whisperCPP: return true
        default: return false
        }
    }

    /// Keychain account name, or nil when the provider needs no key.
    var keychainAccount: String? {
        switch self {
        case .appleSpeech, .whisperCPP: return nil
        case .openAIWhisper: return "openai"
        case .groqWhisper: return "groq"
        case .deepgram: return "deepgram"
        case .assemblyAI: return "assemblyai"
        }
    }

    var defaultModel: String {
        switch self {
        case .appleSpeech: return "on-device"
        case .whisperCPP: return "ggml-base.en"
        case .openAIWhisper: return "whisper-1"
        case .groqWhisper: return "whisper-large-v3-turbo"
        case .deepgram: return "nova-2"
        case .assemblyAI: return "best"
        }
    }
}

// MARK: - Text providers

enum TextProviderKind: String, CaseIterable, Identifiable, Codable {
    case anthropic
    case openAI
    case googleGemini
    case openRouter
    case groq
    case deepSeek
    case mistral
    case ollama
    case lmStudio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openAI: return "OpenAI"
        case .googleGemini: return "Google Gemini"
        case .openRouter: return "OpenRouter"
        case .groq: return "Groq"
        case .deepSeek: return "DeepSeek"
        case .mistral: return "Mistral"
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        }
    }

    var isLocal: Bool {
        switch self {
        case .ollama, .lmStudio: return true
        default: return false
        }
    }

    var keychainAccount: String? {
        switch self {
        case .ollama, .lmStudio: return nil
        case .anthropic: return "anthropic"
        case .openAI: return "openai"
        case .googleGemini: return "gemini"
        case .openRouter: return "openrouter"
        case .groq: return "groq"
        case .deepSeek: return "deepseek"
        case .mistral: return "mistral"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-opus-5"
        case .openAI: return "gpt-4.1"
        case .googleGemini: return "gemini-2.5-flash"
        case .openRouter: return "anthropic/claude-opus-5"
        case .groq: return "llama-3.3-70b-versatile"
        case .deepSeek: return "deepseek-chat"
        case .mistral: return "mistral-small-latest"
        case .ollama: return "qwen3:8b"
        case .lmStudio: return "local-model"
        }
    }

    /// Base URL for the OpenAI-compatible chat completions endpoint.
    var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com"
        case .openAI: return "https://api.openai.com/v1"
        case .googleGemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .deepSeek: return "https://api.deepseek.com/v1"
        case .mistral: return "https://api.mistral.ai/v1"
        case .ollama: return "http://localhost:11434"
        case .lmStudio: return "http://localhost:1234/v1"
        }
    }
}

// MARK: - Dictation language

/// The languages offered for pinning. Auto-detection covers far more than this
/// — the point of the list is the cases where detection guesses wrong, which is
/// most often on short recordings and on English spoken with a strong accent.
///
/// Shared by Settings and the recording popup, so a language can be pinned
/// before speaking or mid-recording once it's clear detection has gone astray.
enum DictationLanguage {
    static let auto = "auto"

    static let pinnable: [(code: String, name: String)] = [
        ("en-US", "English (US)"), ("en-GB", "English (UK)"), ("de-DE", "German"),
        ("fr-FR", "French"), ("es-ES", "Spanish"), ("it-IT", "Italian"),
        ("pt-BR", "Portuguese (Brazil)"), ("nl-NL", "Dutch"), ("tr-TR", "Turkish"),
        ("ja-JP", "Japanese"), ("ko-KR", "Korean"), ("zh-CN", "Chinese (Simplified)"),
    ]

    static func name(for code: String) -> String {
        code == auto
            ? "Detect automatically"
            : pinnable.first { $0.code == code }?.name ?? code
    }

    /// What fits in the recording pill: "Auto", "EN", "TR".
    static func badge(for code: String) -> String {
        code == auto ? "Auto" : String(code.prefix(2)).uppercased()
    }
}

// MARK: - Improvement modes

struct ImprovementMode: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var prompt: String
    var isBuiltIn: Bool

    static let builtIns: [ImprovementMode] = [
        .init(id: "professional", name: "Professional", isBuiltIn: true,
              prompt: "Rewrite in clear professional prose. Keep it businesslike and precise without becoming stiff or formal for its own sake."),
        .init(id: "friendly", name: "Friendly", isBuiltIn: true,
              prompt: "Rewrite in a warm, conversational voice, as if writing to a colleague you know well. Keep contractions."),
        .init(id: "concise", name: "Concise", isBuiltIn: true,
              prompt: "Tighten aggressively. Cut filler, repetition, and hedging. Keep every fact and every distinct point the speaker made."),
        .init(id: "detailed", name: "Detailed", isBuiltIn: true,
              prompt: "Expand the speaker's own points into complete, well-structured sentences. Do not introduce facts, examples, or claims the speaker did not make."),
        .init(id: "email", name: "Email", isBuiltIn: true,
              prompt: "Format as an email body. Do not invent a subject line, greeting, or sign-off unless the speaker dictated one."),
        .init(id: "meeting", name: "Meeting Notes", isBuiltIn: true,
              prompt: "Format as meeting notes: short topic headings and bullet points. Put anything the speaker flagged as an action item under an \"Action items\" heading. Do not invent action items."),
        .init(id: "markdown", name: "Markdown", isBuiltIn: true,
              prompt: "Format as Markdown, using headings, lists, and emphasis where the structure of what was said calls for them."),
        .init(id: "verbatim", name: "Verbatim", isBuiltIn: true,
              prompt: "Fix only grammar, spelling, and punctuation. Do not restructure sentences, change word choice, or alter the register."),
    ]

    init(id: String, name: String, isBuiltIn: Bool, prompt: String) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.prompt = prompt
    }
}

// MARK: - Audio retention

enum AudioRetention: String, CaseIterable, Identifiable, Codable {
    case deleteAfterTranscription
    case keep30Days
    case keepForever

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deleteAfterTranscription: return "Delete after transcription"
        case .keep30Days: return "Keep for 30 days"
        case .keepForever: return "Keep indefinitely"
        }
    }

    var detail: String {
        switch self {
        case .deleteAfterTranscription: return "Recommended. Only the text is kept."
        case .keep30Days: return "Lets you re-transcribe recent notes with a different provider."
        case .keepForever: return "Uses the most disk space."
        }
    }
}
