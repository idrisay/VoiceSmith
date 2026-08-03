# VoiceSmith

## Speak naturally. Write beautifully.

> VoiceSmith is an AI-powered voice-to-text application that transforms spoken thoughts into polished writing.
>
> **v1 targets macOS only.** iOS and a Progressive Web App are planned, but are explicitly out of scope until the macOS app ships. See [Later Platforms](#later-platforms).

---

# Scope

## In scope for v1

- A native macOS application.
- Local-first storage. No account, no login, no backend.
- Bring-your-own API keys for cloud providers, stored in the macOS Keychain.
- Fully offline operation when a local model is selected.

## Out of scope for v1

- iOS and web clients.
- Backend services, sync, and multi-device support.
- User accounts, billing, and usage quotas.
- Team or sharing features.

Deferring the backend is a deliberate decision: it removes authentication, sync conflicts, GDPR data-processing obligations, and hosting cost from v1 entirely.

---

# Product Vision

VoiceSmith removes the friction between thinking and writing.

A user should be able to:

1. Press a global keyboard shortcut from any application.
2. Speak naturally.
3. Receive polished text within seconds.
4. Paste it where they were already working.

The shortcut-to-paste round trip is the product. Everything else supports it.

---

# macOS Application

A native productivity utility that lives in the menu bar.

Features:

- Menu bar application, no Dock icon by default
- Global keyboard shortcut
- Floating recording window
- Clipboard integration
- Automatic paste into the frontmost application
- Notifications
- Note history with search
- Launch at login

---

# Core User Flow

## 1. Invoke

The user presses the global shortcut, or clicks the menu bar icon.

VoiceSmith:

- Requests microphone permission on first use.
- Captures the focused text field, before anything can move focus away from it.
- Shows the floating recording window just below the caret, falling back to the pointer when the app reports no caret position.
- Begins recording immediately, without waiting for the window animation.

The focused field is captured first because showing the window or requesting a permission can move focus, and by then the caret is gone.

## 2. Record

The recording window shows:

- A live waveform.
- An elapsed timer.
- The active transcription and improvement providers.

Controls:

- Pause
- Resume
- Stop
- Cancel

Behaviour:

- Pressing the global shortcut again stops the recording.
- Pressing `Escape` cancels and discards the audio.
- Recording stops automatically at a configurable maximum length. Default: 10 minutes.

## 3. Transcribe

On stop, VoiceSmith:

- Shows a transcribing indicator with a cancel control.
- Sends the audio to the selected speech provider.
- Produces a raw transcript.

## 4. Improve

The raw transcript is passed to the selected text provider using the active mode.

- The improved text is shown alongside the raw transcript.
- The user can toggle between raw and improved output.
- If improvement fails, the raw transcript is used and the failure is reported.

## 5. Deliver

By default, VoiceSmith:

- Copies the improved text to the clipboard.
- Inserts it into the text field that was focused at invocation.
- Shows a confirmation notification.
- Saves the note to local history.

Each of these is individually configurable. A user who only wants the clipboard filled should be able to turn off insertion.

## Insertion

Insertion targets the specific field, not just the application:

- The text is written to the focused element at the caret, replacing any selection. This leaves the clipboard untouched and does not depend on the app honouring a synthetic keystroke.
- Apps that reject a direct write — web views and Electron apps, mostly — fall back to reactivating the app and sending `⌘V`.
- **When no editable text field was focused, nothing is inserted.** The text goes to the clipboard and the notification says so. Firing `⌘V` at whatever happens to be frontmost would put text somewhere the user never asked for.

The recording window states the destination for the whole session — either the field it will insert into, or that this one is clipboard-only — so the outcome is never a surprise.

Insertion requires Accessibility permission. Without it VoiceSmith cannot see the focused field at all, so it degrades to clipboard-only and says why.

## 6. Review

From the history window, the user can:

- Read, edit, copy, and delete notes.
- Re-run improvement with a different mode or model.
- Search across transcripts and improved text.
- Tag and favourite notes.

---

# Error and Edge Cases

Every one of these must have defined behaviour before implementation begins.

| Case | Behaviour |
|-|-|
| Microphone permission denied | Explain why it is needed, link to System Settings, do not retry silently |
| No microphone available | Disable recording, show the reason in the menu bar |
| Input device disconnected mid-recording | Stop, keep the audio captured so far, offer to transcribe it |
| No network, cloud provider selected | Offer to retry, switch to a local model, or keep the audio for later |
| Missing or invalid API key | Open provider settings directly, name the provider |
| Transcription fails | Keep the audio, allow retry with a different provider |
| Improvement fails or times out | Fall back to the raw transcript, report the failure |
| Silent or empty recording | Discard without calling a provider, notify the user |
| Local model not installed | Link to installation instructions, offer a cloud fallback |
| Disk full | Refuse to record rather than lose audio mid-capture |

---

# Speech Recognition

## Local

- Apple Speech framework
- Whisper.cpp
- Faster Whisper
- Whisper models through Ollama

## Cloud

- OpenAI Whisper
- Groq Whisper
- Deepgram
- AssemblyAI
- Google Speech
- Azure Speech

## Language

- Automatic language detection by default.
- A manual language override in settings.
- The detected language is stored on the note.
- Improvement is performed in the transcript's language, never translated unless the user asks.

---

# AI Text Improvement

The selected model improves:

- Grammar
- Spelling
- Punctuation
- Readability
- Structure
- Formatting

Modes:

- Professional
- Friendly
- Concise
- Detailed
- Email
- Meeting Notes
- Markdown

Users can define custom modes with their own prompt.

---

# AI Rules

The model must:

- Preserve the original meaning.
- Keep important information.
- Avoid hallucination.
- Avoid unnecessary rewriting.
- Never answer the content as if it were a question addressed to it.
- Return only the improved text, with no preamble or commentary.

VoiceSmith improves writing; it does not replace the user's thoughts.

---

# Provider Architecture

Speech and text providers are independent and separately configurable. A user may transcribe locally and improve in the cloud, or the reverse.

## Text providers

### Cloud

- Anthropic
- OpenAI
- Google Gemini
- OpenRouter
- Groq
- DeepSeek
- Mistral
- Any OpenAI-compatible endpoint

### Local

- Ollama
- LM Studio
- llama.cpp

## Interface

```swift
protocol SpeechProvider {
    func transcribe(_ audio: AudioFile, language: Language?) async throws -> Transcript
}

protocol TextProvider {
    func improve(_ text: String, mode: ImprovementMode) async throws -> String
}
```

Adding a provider means implementing one of these. No other part of the application changes.

## Key storage

- API keys are stored in the macOS Keychain, never in preferences or plain files.
- Keys are never written to logs, crash reports, or analytics.
- Requests go directly from the app to the provider. VoiceSmith operates no proxy in v1.

---

# Local AI Support

Fully offline operation requires a local speech model and a local text model.

- Speech: Apple Speech framework, or Whisper.cpp with a downloaded model.
- Text: Ollama, LM Studio, or llama.cpp.

VoiceSmith detects a running Ollama instance and lists its installed models automatically.

## Recommended Ollama models

Defaults ship as configuration, not as hardcoded values, so this table can change without a release.

| Model | RAM | Quality | Recommendation |
|-|-|-|-|
| Qwen 3 8B | 8 GB | Excellent | Default |
| Gemma 3 12B | 12 GB | Excellent | Quality |
| Mistral Small | 8 GB | Very good | Fast |
| Phi-4 | 6 GB | Good | Lightweight |
| Llama 3.3 | 16 GB+ | Excellent | High-end devices |
| DeepSeek R1 Distill | 16 GB+ | Excellent | Advanced reasoning |

---

# Architecture

```
        Global shortcut / menu bar
                    │
                    ▼
            Recording window
                    │
                    ▼
             Audio capture              (AVFoundation)
                    │
                    ▼
             SpeechProvider ────────────┬── Apple Speech
                    │                   ├── Whisper.cpp
                    │                   └── Cloud APIs
                    ▼
              TextProvider ─────────────┬── Ollama / LM Studio
                    │                   └── Anthropic / OpenAI / …
                    ▼
         Clipboard, paste, notification
                    │
                    ▼
            Local store (SwiftData)
```

---

# Technology Stack

Language:

- Swift

Framework:

- SwiftUI, with AppKit where the menu bar and floating window require it

Architecture:

- MVVM

Frameworks:

- AVFoundation — audio capture
- Speech — on-device transcription
- SwiftData — local persistence
- Security — Keychain access
- UserNotifications — completion notifications

Global shortcuts and automatic pasting require Accessibility permission. This must be requested with a clear explanation, and the app must remain usable without it.

---

# Data Model

```
VoiceNote
    id              UUID
    createdAt       Date
    updatedAt       Date
    duration        TimeInterval
    audioPath       URL?          // nil once audio is discarded
    rawTranscript   String
    improvedText    String?
    language        String
    mode            String
    speechProvider  String
    speechModel     String
    textProvider    String?
    textModel       String?
    tags            [String]
    isFavorite      Bool
```

Fields are named so that a future sync layer can add `deletedAt`, `syncedAt`, and `deviceId` without migrating existing data.

## Audio retention

- Audio is written to the application support directory.
- Default retention: deleted immediately after successful transcription.
- Alternatives: keep for 30 days, or keep indefinitely.
- The setting is shown during onboarding, not buried in preferences.

---

# Security and Privacy

- API keys in the Keychain, encrypted at rest.
- No telemetry in v1. If analytics are added later, they are opt-in and never include note content.
- Audio and transcripts never leave the machine unless a cloud provider is explicitly selected.
- The active provider is always visible in the recording window, so the user knows whether the recording is leaving the device.
- Sandboxed, with the hardened runtime, notarized for distribution.
- No sensitive values in logs or crash reports.

Because v1 stores no data on any server, GDPR obligations are limited to what ships in the app. Cloud providers are the user's own accounts under their own agreements, which the provider settings screen states plainly.

---

# Offline Support

With local models selected, VoiceSmith is fully functional with no network connection:

- Recording
- Transcription
- Improvement
- History and search

With cloud providers selected and no network, recordings are queued and the user is offered a local fallback.

---

# Performance Goals

- Launch to menu bar: under 1 second.
- Shortcut press to recording started: under 200 ms.
- Idle memory: under 100 MB.
- No measurable CPU use while idle.
- Cloud transcription of one minute of audio: under 5 seconds.

---

# Success Criteria for v1

VoiceSmith v1 succeeds if it is:

- The fastest way to get spoken thoughts into any macOS text field.
- Usable entirely offline, with no account and no cloud dependency.
- A native Mac application, not a wrapped web app.

Release target:

- macOS App Store, with a direct notarized download alongside it.

The direct download matters: App Store sandboxing may restrict Accessibility-based automatic pasting.

---

# Later Platforms

Deliberately deferred. Listed here so that v1 decisions do not foreclose them.

## iOS

- Instant recording
- Lock screen widget
- Control Center shortcut
- Siri Shortcut
- Share Extension
- Background recording

## Web PWA

- Installable PWA
- Browser microphone access
- Offline shell and notes via Service Worker
- Local inference through WebGPU and Transformers.js where supported

Browser-local transcription is substantially slower and less accurate than native. Offline PWA support means degraded quality, not parity, and should be described that way to users.

## Sync

Multi-device support requires a decision that v1 avoids: CloudKit, or a custom backend.

- **CloudKit** — no servers, no accounts, no hosting cost, but Apple platforms only. A web client cannot use it.
- **Custom backend** — works everywhere, but adds authentication, hosting, and data-protection obligations.

Choosing CloudKit for iOS makes the PWA significantly harder later. This decision should be made when iOS work begins, not before.

## Other

- Apple Watch and iPad
- Vision Pro
- Browser extensions
- Meeting summaries and action items
- Personal AI writing style
- Semantic search and chat with notes
- Translation


