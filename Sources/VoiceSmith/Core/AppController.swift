import AVFoundation
import AppKit
import Combine
import Foundation

/// The pipeline: invoke → record → transcribe → improve → deliver → review.
@MainActor
final class AppController: ObservableObject {

    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case improving
        case filingTasks
        case done(noteID: UUID)
        case failed(VoiceSmithError)

        var isBusy: Bool {
            switch self {
            case .recording, .transcribing, .improving, .filingTasks: return true
            default: return false
            }
        }
    }

    /// What the current recording is for. Set at invoke, because it's the
    /// trigger the user reached for that says what they meant — double-tap
    /// Option means "this is a to-do" before a word has been spoken.
    enum CaptureIntent { case text, todo }
    @Published private(set) var intent: CaptureIntent = .text

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var statusDetail: String = ""
    /// Audio kept aside after a failure so the user can retry without re-dictating.
    @Published private(set) var pendingAudio: URL?
    /// The text field captured at invoke. Drives both panel placement and delivery.
    @Published private(set) var target: FocusedInput = .none
    /// How the last to-do capture ended.
    ///
    /// Both outcomes get shown. Filing nothing is the correct response to
    /// "thank you" or a stray silence, but it looks identical to a broken
    /// feature unless the app says so — and the user pressed a key on purpose,
    /// so they are owed an answer either way.
    /// Where something was filed, so the confirmation can offer the right app.
    /// Sending someone to Reminders to look for a calendar entry is a small
    /// betrayal of a button that says "open".
    enum Destination: Equatable, Hashable {
        case reminders, calendar

        var appName: String {
            switch self {
            case .reminders: return "Reminders"
            case .calendar:  return "Calendar"
            }
        }

        /// Verified to resolve: ical:// → Calendar.app,
        /// x-apple-reminderkit:// → Reminders.app.
        var url: URL {
            switch self {
            case .reminders: return URL(string: "x-apple-reminderkit://")!
            case .calendar:  return URL(string: "ical://")!
            }
        }
    }

    enum TodoOutcome: Equatable, Hashable {
        case filed([ExtractedTask], to: Destination)
        /// Nothing in what was said described something to do. Carries the
        /// transcript, because seeing what was heard is usually the explanation.
        case nothingFound(heard: String)
    }
    /// An offer to file what the last dictation sounded like. Purely additive:
    /// the text has already been delivered by the time this appears, so
    /// ignoring it costs nothing and is the common case.
    @Published private(set) var offeredAction: DetectedAction?
    private var filedEventID: String?

    /// Non-nil only while the confirmation is on screen. Undo lives exactly as
    /// long as this does; past that, Reminders owns what was filed.
    @Published private(set) var todoOutcome: TodoOutcome?
    private var filedReminderIDs: [String] = []

    let recorder = AudioRecorder()
    let settings: AppSettings
    let store: NoteStore

    private var work: Task<Void, Never>?
    private var windowPresenter: ((CGRect?) -> Void)?
    private var windowDismisser: (() -> Void)?

    init(settings: AppSettings, store: NoteStore) {
        self.settings = settings
        self.store = store

        recorder.onInterruption = { [weak self] error, url in
            Task { @MainActor in self?.handleInterruption(error, audio: url) }
        }
    }

    func attachWindow(present: @escaping (CGRect?) -> Void, dismiss: @escaping () -> Void) {
        windowPresenter = present
        windowDismisser = dismiss
    }

    // MARK: - Invoke

    /// The global shortcut and the menu bar item both land here. Pressing again
    /// while recording stops — that's the one-key round trip the product is built on.
    func toggle(intent: CaptureIntent = .text) {
        switch phase {
        case .recording:
            stopAndProcess()
        case .idle, .done, .failed:
            beginRecording(intent: intent)
        case .transcribing, .improving, .filingTasks:
            break // Already working; ignore.
        }
    }

    func beginRecording(intent: CaptureIntent = .text) {
        self.intent = intent

        // The previous dictation's to-dos are no longer undoable once a new one
        // starts — the panel that offered it is about to show something else.
        todoOutcome = nil
        filedReminderIDs = []
        offeredAction = nil
        filedEventID = nil

        // Capture the focused field *first*: showing the panel or requesting
        // permission can move focus, and by then the caret is gone.
        target = FocusedInput.capture()

        Task { @MainActor in
            guard await ensureMicrophoneAccess() else {
                present(.microphonePermissionDenied)
                return
            }

            do {
                try recorder.start(maxSeconds: TimeInterval(settings.maxRecordingSeconds))
                phase = .recording
                statusDetail = ""
                pendingAudio = nil
                // Anchor the panel to the caret so it appears where the user is
                // already looking; fall back to the pointer when the app doesn't
                // report a caret position.
                windowPresenter?(target.caretRect)
            } catch let error as VoiceSmithError {
                present(error)
            } catch {
                present(.recordingFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Controls

    func pause() { recorder.pause() }
    func resume() { recorder.resume() }

    /// Escape: throw the audio away and get out of the way.
    func cancel() {
        work?.cancel()
        recorder.cancel()
        phase = .idle
        statusDetail = ""
        pendingAudio = nil
        todoOutcome = nil
        filedReminderIDs = []
        offeredAction = nil
        windowDismisser?()
    }

    func stopAndProcess() {
        guard phase == .recording else { return }
        let duration = recorder.duration
        guard let audio = recorder.stop() else {
            // Nothing worth sending to a provider — don't spend a request on silence.
            present(.emptyRecording)
            return
        }
        process(audio: audio, duration: duration)
    }

    /// Retry after a failure, reusing the audio we held back.
    func retryPending() {
        guard let audio = pendingAudio else { return }
        process(audio: audio, duration: durationOf(audio))
    }

    func discardPending() {
        if let audio = pendingAudio {
            try? FileManager.default.removeItem(at: audio)
        }
        pendingAudio = nil
        phase = .idle
        windowDismisser?()
    }

    // MARK: - Pipeline

    private func process(audio: URL, duration: TimeInterval) {
        work?.cancel()
        work = Task { @MainActor in
            do {
                // 1. Transcribe.
                phase = .transcribing
                statusDetail = settings.speechProvider.displayName
                let speech = try ProviderFactory.speech(settings)
                let transcript = try await speech.transcribe(
                    audio: audio,
                    language: settings.language == "auto" ? nil : settings.language,
                    vocabulary: settings.vocabulary
                )
                try Task.checkCancellation()

                // 2. Double-tap Option said this is a to-do before a word was
                // spoken, so the whole transcript is the task: no improvement,
                // no insertion, straight to Reminders.
                if intent == .todo {
                    try await runTodoCapture(
                        transcript: transcript,
                        audio: audio,
                        duration: duration
                    )
                    return
                }

                // 3. Improve. A failure here is non-fatal: the raw transcript is
                // still worth delivering, so we report and continue.
                var improved: String?
                var textProviderName: String?
                var textModelName: String?
                var improvementError: VoiceSmithError?

                if settings.improveAutomatically {
                    phase = .improving
                    statusDetail = settings.textProvider.displayName
                    do {
                        let text = try ProviderFactory.text(settings)
                        improved = try await text.improve(
                            transcript.text,
                            mode: settings.activeMode,
                            language: settings.language,
                            vocabulary: settings.vocabulary
                        )
                        textProviderName = settings.textProvider.displayName
                        textModelName = settings.textModel
                    } catch let error as VoiceSmithError {
                        improvementError = error
                    }
                }
                try Task.checkCancellation()

                // 3. Persist.
                let keepAudio = settings.audioRetention != .deleteAfterTranscription
                let note = VoiceNote(
                    duration: duration,
                    audioPath: keepAudio ? audio.path : nil,
                    rawTranscript: transcript.text,
                    improvedText: improved,
                    language: transcript.language,
                    mode: settings.activeMode.name,
                    speechProvider: settings.speechProvider.displayName,
                    speechModel: settings.speechModel,
                    textProvider: textProviderName,
                    textModel: textModelName
                )
                store.insert(note)
                if !keepAudio {
                    try? FileManager.default.removeItem(at: audio)
                }

                // 4. Deliver. This happens before any task filing, so the text
                // reaches the user whatever the to-do step goes on to do.
                deliver(note.displayText)
                pendingAudio = nil

                // 5. File to-dos, when asked. Deliberately last and deliberately
                // non-fatal: the dictation is already delivered by this point, so
                // a failure here costs the user their tasks, never their words.
                var taskError: VoiceSmithError?
                if settings.addToTaskList {
                    do {
                        try await fileTasks(from: note.displayText)
                    } catch let error as VoiceSmithError {
                        taskError = error
                    }
                }
                try Task.checkCancellation()

                // 6. Offer to file it, if it sounded like an appointment or a
                // task. Deliberately after delivery and deliberately silent on
                // failure: this is a bonus button, and a dictation must never be
                // slower or less reliable because of one.
                if settings.offerDetectedActions,
                   improvementError == nil,
                   ActionHint.isPresent(in: note.displayText) {
                    offeredAction = try? await ProviderFactory.text(settings)
                        .detectAction(in: note.displayText, now: Date())
                }

                phase = .done(noteID: note.id)

                // Improvement failing is the more serious of the two — it means
                // the text delivered was the raw transcript — so it wins the
                // one slot the panel has for saying what went wrong.
                if let problem = improvementError ?? taskError {
                    statusDetail = problem.errorDescription ?? "Something didn't finish"
                    present(problem, keepingAudio: nil)
                } else {
                    statusDetail = ""
                    // Hold the panel open while there's an undo to offer; the
                    // tasks are in the user's own list from here on.
                    if todoOutcome == nil, offeredAction == nil { windowDismisser?() }
                }
            } catch is CancellationError {
                phase = .idle
                windowDismisser?()
            } catch let error as VoiceSmithError {
                // Keep the audio: the user shouldn't have to say it all again.
                present(error, keepingAudio: error == .emptyRecording ? nil : audio)
            } catch {
                present(
                    .transcriptionFailed(
                        provider: settings.speechProvider.displayName,
                        detail: error.localizedDescription
                    ),
                    keepingAudio: audio
                )
            }
        }
    }

    // MARK: - To-dos

    /// Runs a dictation captured with double-tap Option.
    ///
    /// Every failure path here ends by delivering the words the normal way. The
    /// user asked for a reminder, and not getting one is a disappointment — but
    /// silently swallowing a sentence they spoke, because a permission or an API
    /// key was missing, would be a bug. Text they didn't want is easy to delete;
    /// text that vanished is gone.
    private func runTodoCapture(
        transcript: Transcript,
        audio: URL,
        duration: TimeInterval
    ) async throws {
        let spoken = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let keepAudio = settings.audioRetention != .deleteAfterTranscription
        let note = VoiceNote(
            duration: duration,
            audioPath: keepAudio ? audio.path : nil,
            rawTranscript: transcript.text,
            improvedText: nil,
            language: transcript.language,
            mode: "To-do",
            speechProvider: settings.speechProvider.displayName,
            speechModel: settings.speechModel,
            textProvider: nil,
            textModel: nil
        )
        store.insert(note)
        if !keepAudio { try? FileManager.default.removeItem(at: audio) }
        pendingAudio = nil

        // Nothing but silence or punctuation came back. No reason to spend a
        // model call finding out there is no task in it.
        guard !spoken.isEmpty else {
            phase = .done(noteID: note.id)
            windowDismisser?()
            return
        }

        // Ask for Reminders here if it has never been asked. macOS only lists an
        // app under Privacy & Security once it has requested, so telling a user
        // who has never been prompted to "enable VoiceSmith in System Settings"
        // would send them to look for a row that isn't there. This is also the
        // one moment the request explains itself: they just asked for a to-do.
        if !RemindersService.shared.isAuthorized, !RemindersService.shared.hasBeenAsked {
            await RemindersService.shared.requestAccess()
        }

        guard RemindersService.shared.isAuthorized else {
            deliver(spoken)
            phase = .done(noteID: note.id)
            present(.remindersPermissionDenied, keepingAudio: nil)
            return
        }

        do {
            try await fileTasks(from: spoken)
        } catch let error as VoiceSmithError {
            deliver(spoken)
            phase = .done(noteID: note.id)
            present(error, keepingAudio: nil)
            return
        }

        phase = .done(noteID: note.id)

        // An explicit command that produced nothing needs saying out loud. When
        // filing runs off the toggle, silence is the right answer — the user
        // wasn't asking. Here they were.
        statusDetail = ""
        if todoOutcome == nil {
            todoOutcome = .nothingFound(heard: spoken)
        }
    }

    /// Extracts action items and writes them to Reminders.
    ///
    /// Two things are worth noticing about the order here. Permission is checked
    /// before the model call, so a user who never granted it isn't billed for
    /// extraction that can't be used. And nothing is written when the model finds
    /// no tasks — most dictation isn't a to-do list, and silence is the correct
    /// response to that, not an empty reminder.
    private func fileTasks(from text: String) async throws {
        guard RemindersService.shared.isAuthorized else {
            throw VoiceSmithError.remindersPermissionDenied
        }

        phase = .filingTasks
        statusDetail = settings.textProvider.displayName

        let provider = try ProviderFactory.text(settings)
        let tasks = try await provider.extractTasks(from: text, now: Date())
        guard !tasks.isEmpty else { return }

        try Task.checkCancellation()
        filedReminderIDs = try RemindersService.shared.save(
            tasks,
            toListWithID: settings.reminderListID
        )
        todoOutcome = .filed(tasks, to: .reminders)

        if settings.showNotification {
            Delivery.notify(
                title: tasks.count == 1 ? "1 to-do added" : "\(tasks.count) to-dos added",
                body: tasks.map(\.title).joined(separator: "\n")
            )
        }
    }

    /// Takes back what the last dictation filed. The panel offers this only while
    /// it's on screen — past that the reminders belong to Reminders.
    func undoFiledTasks() {
        RemindersService.shared.remove(identifiers: filedReminderIDs)
        if let filedEventID { CalendarService.shared.remove(identifier: filedEventID) }
        self.filedEventID = nil
        filedReminderIDs = []
        todoOutcome = nil
        statusDetail = ""
        windowDismisser?()
    }

    // MARK: - Offered actions

    /// The user picked a destination for what was detected.
    ///
    /// Permission is asked for here, at the only moment it explains itself: they
    /// have just pressed a button that says "Add to Calendar". Asking at launch
    /// would be a prompt with no context, and macOS won't list the app under
    /// Privacy & Security until it has asked at least once — so directing them
    /// there first would send them looking for a row that doesn't exist.
    func acceptOfferedAction(as kind: DetectedAction.Kind) {
        guard let action = offeredAction else { return }
        offeredAction = nil

        Task { @MainActor in
            do {
                switch kind {
                case .event:
                    if !CalendarService.shared.isAuthorized, !CalendarService.shared.hasBeenAsked {
                        await CalendarService.shared.requestAccess()
                    }
                    filedEventID = try CalendarService.shared.save(
                        action, toCalendarWithID: settings.calendarID
                    )
                    todoOutcome = .filed([action.asTask], to: .calendar)
                case .reminder:
                    if !RemindersService.shared.isAuthorized, !RemindersService.shared.hasBeenAsked {
                        await RemindersService.shared.requestAccess()
                    }
                    filedReminderIDs = try RemindersService.shared.save(
                        [action.asTask], toListWithID: settings.reminderListID
                    )
                    todoOutcome = .filed([action.asTask], to: .reminders)
                }
            } catch let error as VoiceSmithError {
                present(error, keepingAudio: nil)
            } catch {
                present(.calendarUnavailable(detail: error.localizedDescription), keepingAudio: nil)
            }
        }
    }

    /// No thanks. The text is already where it was going.
    func declineOfferedAction() {
        offeredAction = nil
        statusDetail = ""
        windowDismisser?()
    }

    /// Dismisses the confirmation without touching what was filed. Called by the
    /// buttons and by the countdown alike — doing nothing is a valid answer, and
    /// the common one.
    func acknowledgeTodoOutcome() {
        filedReminderIDs = []
        filedEventID = nil
        todoOutcome = nil
        statusDetail = ""
        windowDismisser?()
    }

    private func deliver(_ text: String) {
        if settings.copyToClipboard {
            Delivery.copyToClipboard(text)
        }

        // Attempt insertion whenever it's switched on. Detection of "is this a
        // text field" is unreliable across browsers and Electron apps, and
        // refusing to paste on a failed detection silently did nothing in the
        // most common case. ⌘V into a non-text context is harmless by comparison.
        if settings.autoPaste {
            do {
                let method = try Delivery.insert(
                    text,
                    into: target,
                    copiedToClipboard: settings.copyToClipboard
                )
                UserDefaults.standard.set(
                    "\(method) into \(target.describedTarget ?? "frontmost app") [\(Delivery.lastAttemptDetail)]",
                    forKey: "diagnostic.lastDelivery"
                )
            } catch let error as VoiceSmithError {
                UserDefaults.standard.set("failed: \(error)", forKey: "diagnostic.lastDelivery")
                // The clipboard still holds it — degrade rather than fail.
                statusDetail = error.errorDescription ?? ""
                if settings.showNotification {
                    Delivery.notify(
                        title: "Copied, but not inserted",
                        body: error.recoverySuggestion ?? ""
                    )
                }
                return
            } catch {}
        }

        if settings.showNotification {
            let preview = text.count > 80 ? String(text.prefix(80)) + "…" : text
            let title = settings.autoPaste
                ? "VoiceSmith"
                : "Copied to clipboard — press ⌘V to paste"
            Delivery.notify(title: title, body: preview)
        }
    }

    // MARK: - Re-run

    /// Re-improve an existing note with the current mode and model.
    func reimprove(_ note: VoiceNote, mode: ImprovementMode) {
        Task { @MainActor in
            do {
                let provider = try ProviderFactory.text(settings)
                let improved = try await provider.improve(
                    note.rawTranscript,
                    mode: mode,
                    language: settings.language,
                    vocabulary: settings.vocabulary
                )
                note.improvedText = improved
                note.mode = mode.name
                note.textProvider = settings.textProvider.displayName
                note.textModel = settings.textModel
                store.touch(note)
            } catch let error as VoiceSmithError {
                present(error, keepingAudio: nil)
            } catch {}
        }
    }

    // MARK: - Errors

    private func handleInterruption(_ error: VoiceSmithError, audio: URL?) {
        guard phase == .recording else { return }
        // Device disconnect or the length cap: keep what we captured and offer it.
        present(error, keepingAudio: audio)
    }

    private func present(_ error: VoiceSmithError, keepingAudio audio: URL? = nil) {
        pendingAudio = audio
        phase = .failed(error)
        windowPresenter?(target.caretRect)
        if settings.showNotification {
            Delivery.notify(
                title: error.errorDescription ?? "VoiceSmith",
                body: error.recoverySuggestion ?? ""
            )
        }
    }

    func dismissError() {
        guard case .failed = phase else { return }
        phase = .idle
        windowDismisser?()
    }

    // MARK: - Permissions

    private func ensureMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    private func durationOf(_ url: URL) -> TimeInterval {
        (try? AVAudioPlayer(contentsOf: url).duration) ?? 0
    }
}
