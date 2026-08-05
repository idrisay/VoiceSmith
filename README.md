# VoiceSmith

**Speak naturally. Write beautifully.**

A macOS menu bar app that turns dictation into finished writing, without leaving the app you're already in. Double-tap `Shift`, speak, double-tap again — the polished text appears in the text field you were typing in.

Everything is stored on your Mac. There's no account, no sign-in, and no server of ours. With a local model selected, nothing leaves the machine at all.

![Menu bar states](docs/menu-bar-states.png)

*Idle, recording, working, and needs-attention — shown on dark and light menu bars.*

---

## How it works

1. **Double-tap `Shift`** from any application
2. **Speak.** A small popup appears at your cursor with a live sound meter
3. **Double-tap `Shift` again.** VoiceSmith transcribes, cleans the text up with an AI model, and writes it into the field you were in

`Escape` cancels and discards the recording.

**The trigger is yours to change.** In **Settings › Shortcut** you can switch the double-tap off and record any key combination you like for start/stop, or keep both. Worth doing if you live in a JetBrains IDE — those use double-tap `Shift` themselves, so until you change it, both will fire.

The transcript is *cleaned*, not rewritten: grammar, punctuation, filler words, and false starts are fixed, but the meaning, the facts, and your voice stay yours.

---

## Requirements

- macOS 14 or later
- Xcode command line tools (`xcode-select --install`)

No API key is required to get started — the default setup transcribes on-device with Apple Speech.

---

## Install

There's no pre-built download yet, so VoiceSmith is compiled on your own Mac. It takes two commands. No GitHub account is needed — this repository is public.

### With Git

```bash
git clone https://github.com/idrisay/VoiceSmith.git
cd VoiceSmith

# One time: create a stable local signing identity (see below for why)
./Scripts/create-signing-identity.sh

# Build and launch
./Scripts/build-app.sh release run
```

### Without Git

Nothing here needs a Git checkout — the build works fine from a plain folder.

1. Download [**the ZIP**](https://github.com/idrisay/VoiceSmith/archive/refs/heads/main.zip) and unzip it. You'll get a folder called `VoiceSmith-main`.
2. Open **Terminal** (⌘Space, type "Terminal"). Type `cd` followed by a space, then **drag the unzipped folder onto the Terminal window** — it fills in the path for you. Press Return.
3. Run these two lines, one at a time:

   ```bash
   ./Scripts/create-signing-identity.sh
   ./Scripts/build-app.sh release run
   ```

If the second command complains about missing developer tools, run `xcode-select --install`, accept the macOS installer, and try again.

To update later, download a fresh ZIP and repeat — or switch to the Git route, where `git pull` and a rebuild is enough.

### Afterwards

`VoiceSmith.app` is built into `build/`. Drag it to `/Applications` if you want it permanently, and rebuild with `./Scripts/build-app.sh release` after pulling changes.

A setup assistant runs on first launch and walks you through providers and permissions.

### If someone hands you a built copy

An app built on someone else's Mac carries *their* local signature, which your Mac doesn't trust. macOS will refuse to open it on the first try.

Right-click the app and choose **Open** — that offers a launch-anyway prompt that double-clicking doesn't. If macOS blocks it regardless, open **System Settings › Privacy & Security**, scroll to the message about VoiceSmith, and click **Open Anyway**. Should both fail, clear the download flag directly:

```bash
xattr -dr com.apple.quarantine /Applications/VoiceSmith.app
```

Building it yourself avoids all of this, and is the recommended route.

### Why the signing step matters

macOS ties permission grants — Accessibility, microphone — to an app's **code signature**. An ad-hoc signature is derived from the binary's contents, so it changes on every build: macOS then treats each rebuild as a different app and silently stops honouring your grants, while leaving a stale entry ticked in System Settings that no longer matches anything. The symptom is Accessibility that's "already enabled" but doesn't work.

`create-signing-identity.sh` creates a self-signed certificate in your login keychain so the signature stays stable and permissions persist across rebuilds. It's local, and undoable:

```bash
security delete-certificate -c "VoiceSmith Dev"
```

Skip it if you like — the build falls back to ad-hoc signing and warns you.

### Permissions

On first launch VoiceSmith asks for what it needs:

| Permission | Why | Required? |
|---|---|---|
| **Microphone** | Recording | Yes |
| **Speech Recognition** | On-device transcription with Apple Speech | Only for Apple Speech |
| **Accessibility** | Detecting the focused text field, writing into it, and double-tap `Shift` | Yes for the default setup |

Without Accessibility, VoiceSmith still works — use the key combination (`⌃⌥⌘Space`) and paste with `⌘V` yourself.

---

## Setup

A setup assistant runs on first launch: pick how speech is transcribed, how text is improved, grant permissions, and choose what happens to recordings. You can re-run it any time from **Settings › General › Setup assistant**.

Everything you change between dictations lives in the menu bar — mode, providers, and delivery. Settings holds what you configure once.

### Providers

Speech and text are configured **independently**. You can transcribe on-device and improve in the cloud, or the reverse.

| | Local | Cloud |
|---|---|---|
| **Speech** | Apple Speech *(default)*, Whisper.cpp | OpenAI, Groq, Deepgram, AssemblyAI |
| **Text** | Ollama, LM Studio | Anthropic *(default)*, OpenAI, Gemini, OpenRouter, Groq, DeepSeek, Mistral |

Cloud providers use **your own API key**, stored in the macOS Keychain and sent directly to that provider. VoiceSmith runs no proxy. Keys are write-only in the interface — it shows whether one is stored, never the value.

For a fully offline setup, pair **Apple Speech** with **Ollama**.

### Modes

Improvement style is a mode: Professional, Friendly, Concise, Detailed, Email, Meeting Notes, Markdown, or Verbatim. Duplicate any of them in **Settings › Modes** to write your own prompt.

---

## Where your data lives

```
~/Library/Application Support/VoiceSmith/
├── notes.store    # transcripts and improved text (SwiftData)
└── Audio/         # recordings, per your retention setting
```

Audio is **deleted after transcription by default**. You can keep it 30 days or indefinitely — the choice is offered during setup rather than buried in preferences.

There is no telemetry.

---

## Adding a provider

The whole app is built around two protocols:

```swift
protocol SpeechProvider {
    func transcribe(audio: URL, language: String?) async throws -> Transcript
}

protocol TextProvider {
    func improve(_ text: String, mode: ImprovementMode, language: String) async throws -> String
}
```

To add a backend: conform to one of them, add a case to the enum in `Support/Catalog.swift`, and wire it up in `Providers/ProviderFactory.swift`. Nothing else changes.

---

## Not implemented

Honest gaps, so you know what you're getting:

- **Google Speech and Azure Speech.** Neither accepts the AAC audio the recorder produces; supporting them needs a second transcode path.
- **Faster Whisper**, and Whisper served through Ollama — Ollama exposes no Whisper endpoint.
- **Editable provider base URLs.** llama.cpp's server is OpenAI-compatible and would work, but the URL is fixed per provider so there's nowhere to point it.
- **iOS and the web PWA.** macOS only for now — see [`app-specs.md`](app-specs.md).
- **Sync.** Notes are local to this Mac by design; there's no backend and no CloudKit.

---

## Troubleshooting

**Double-tap `Shift` does nothing.** Accessibility isn't active. Open the menu bar icon — if it warns about Accessibility, click it. If VoiceSmith already appears in System Settings › Privacy & Security › Accessibility, **remove it and add it again**: a stale entry from a previous build looks enabled but grants nothing.

**The shortcut opens a Finder window.** You pressed `⌥⌘Space`, which macOS reserves for "Show Finder search window". VoiceSmith's key combination is `⌃⌥⌘Space`, and the default trigger is double-tap `Shift`.

**Text is copied but not inserted.** Accessibility again — it's needed to write into another app's field. The text is on your clipboard either way.

**A provider fails.** Errors name the provider and offer the fix; a failed improvement falls back to delivering the raw transcript rather than losing your dictation.

---

## Design notes

[`app-specs.md`](app-specs.md) is the product spec — the user flow, error behaviour, provider architecture, and the reasoning behind the decisions, including the ones deliberately deferred.

---

## License

No license has been chosen yet, so default copyright applies: the source is readable here, but not licensed for reuse or redistribution. If you want others to be able to use or modify it, add a license file.
