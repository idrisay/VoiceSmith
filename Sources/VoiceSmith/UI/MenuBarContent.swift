import AppKit
import SwiftUI

/// The menu bar is the app's control surface — for a utility with no Dock icon
/// and no main window, it's where configuration actually happens. Settings holds
/// the things you set once (keys, shortcut, retention); everything you change
/// between dictations is here.
struct MenuBarContent: View {
    @ObservedObject var controller: AppController
    @ObservedObject var settings: AppSettings
    @ObservedObject var delegate: AppDelegate

    var body: some View {
        primaryAction
        problems

        Divider()

        modeMenu
        speechMenu
        textMenu
        deliveryMenu

        Divider()

        Button("History…") { WindowRouter.shared.openHistory() }
            .keyboardShortcut("h")
        Button("Settings…") { WindowRouter.shared.openSettings() }
            .keyboardShortcut(",")

        Divider()

        Text(routeSummary)

        Button("Quit VoiceSmith") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    // MARK: - Primary

    @ViewBuilder
    private var primaryAction: some View {
        switch controller.phase {
        case .recording:
            Button("Stop and Transcribe") { controller.stopAndProcess() }
            Button("Cancel Recording") { controller.cancel() }
        case .transcribing, .improving:
            Text("Working…")
            Button("Cancel") { controller.cancel() }
        default:
            Button("Start Recording  (\(triggerDescription))") { controller.toggle() }
        }
    }

    /// Anything actively preventing the app from working goes at the top, where
    /// it can't be missed, with the fix one click away.
    @ViewBuilder
    private var problems: some View {
        if let problem = delegate.doubleShiftProblem {
            Button("⚠︎ \(problem) Grant…") { Delivery.requestAccessibilityPermission() }
        }
        if let problem = delegate.shortcutProblem, !settings.triggerOnDoubleShift {
            Button("⚠︎ \(problem) Change…") { WindowRouter.shared.openSettings(.shortcuts) }
        }
        if settings.autoPaste && !Delivery.hasAccessibilityPermission {
            Button("⚠︎ Can't insert text without Accessibility. Grant…") {
                Delivery.requestAccessibilityPermission()
            }
        }
    }

    // MARK: - Configuration

    private var modeMenu: some View {
        Menu("Mode — \(settings.activeMode.name)") {
            ForEach(settings.allModes) { mode in
                Button {
                    settings.modeID = mode.id
                } label: {
                    Text(mode.id == settings.modeID ? "✓  \(mode.name)" : "    \(mode.name)")
                }
            }
            Divider()
            Button("Edit Modes…") { WindowRouter.shared.openSettings(.modes) }
        }
    }

    private var speechMenu: some View {
        Menu("Transcribe — \(settings.speechProvider.displayName)") {
            Section("On this Mac") {
                ForEach(SpeechProviderKind.allCases.filter(\.isLocal)) { kind in
                    speechOption(kind)
                }
            }
            Section("Cloud") {
                ForEach(SpeechProviderKind.allCases.filter { !$0.isLocal }) { kind in
                    speechOption(kind)
                }
            }
            Divider()
            Button("Provider Settings…") { WindowRouter.shared.openSettings(.providers) }
        }
    }

    private func speechOption(_ kind: SpeechProviderKind) -> some View {
        Button {
            settings.speechProvider = kind
            settings.speechModel = kind.defaultModel
        } label: {
            // A cloud provider with no key would fail at the worst moment, so
            // say so here rather than after the user has already spoken.
            Text(label(
                name: kind.displayName,
                selected: kind == settings.speechProvider,
                needsKey: kind.keychainAccount.map { !Keychain.has($0) } ?? false
            ))
        }
    }

    private var textMenu: some View {
        Menu(settings.improveAutomatically
             ? "Improve — \(settings.textProvider.displayName)"
             : "Improve — off") {
            Button {
                settings.improveAutomatically.toggle()
            } label: {
                Text(settings.improveAutomatically ? "✓  Improve with AI" : "    Improve with AI")
            }
            Divider()
            Section("On this Mac") {
                ForEach(TextProviderKind.allCases.filter(\.isLocal)) { kind in
                    textOption(kind)
                }
            }
            Section("Cloud") {
                ForEach(TextProviderKind.allCases.filter { !$0.isLocal }) { kind in
                    textOption(kind)
                }
            }
            Divider()
            Button("Provider Settings…") { WindowRouter.shared.openSettings(.providers) }
        }
    }

    private func textOption(_ kind: TextProviderKind) -> some View {
        Button {
            settings.textProvider = kind
            settings.textModel = kind.defaultModel
            settings.improveAutomatically = true
        } label: {
            Text(label(
                name: kind.displayName,
                selected: kind == settings.textProvider && settings.improveAutomatically,
                needsKey: kind.keychainAccount.map { !Keychain.has($0) } ?? false
            ))
        }
    }

    private var deliveryMenu: some View {
        Menu("Delivery") {
            Button {
                settings.autoPaste.toggle()
            } label: {
                Text(settings.autoPaste
                     ? "✓  Insert into focused field"
                     : "    Insert into focused field")
            }
            Button {
                settings.copyToClipboard.toggle()
            } label: {
                Text(settings.copyToClipboard ? "✓  Copy to clipboard" : "    Copy to clipboard")
            }
            Button {
                settings.showNotification.toggle()
            } label: {
                Text(settings.showNotification ? "✓  Show notification" : "    Show notification")
            }
        }
    }

    /// SwiftUI menus don't expose a checkmark for `Button`, so the state is
    /// carried in the title. Aligned with padding so the labels don't jump.
    private func label(name: String, selected: Bool, needsKey: Bool) -> String {
        let tick = selected ? "✓  " : "    "
        return needsKey ? "\(tick)\(name)  — needs API key" : "\(tick)\(name)"
    }

    // MARK: - Summary

    private var triggerDescription: String {
        settings.triggerOnDoubleShift
            ? "double-tap ⇧"
            : GlobalShortcut.describe(
                keyCode: settings.shortcutKeyCode,
                modifiers: settings.shortcutModifiers
            )
    }

    private var routeSummary: String {
        let route = settings.improveAutomatically
            ? "\(settings.speechProvider.displayName) → \(settings.textProvider.displayName)"
            : settings.speechProvider.displayName
        let privacy = settings.isFullyLocal ? "on this Mac" : "cloud"
        return "\(route)  ·  \(privacy)"
    }
}
