import AppKit
import SwiftUI

/// Read, edit, copy, delete, re-run, search, tag, and favourite — step 6 of the flow.
struct HistoryView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var store: NoteStore
    @ObservedObject var settings: AppSettings

    @State private var query = ""
    @State private var selection: UUID?
    @State private var showFavouritesOnly = false

    private var filtered: [VoiceNote] {
        let base = store.search(query)
        return showFavouritesOnly ? base.filter(\.isFavorite) : base
    }

    private var selected: VoiceNote? {
        filtered.first { $0.id == selection } ?? filtered.first
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let note = selected {
                NoteDetail(note: note, controller: controller, store: store, settings: settings)
                    .id(note.id)
            } else {
                ContentUnavailableView(
                    query.isEmpty ? "No notes yet" : "No matches",
                    systemImage: query.isEmpty ? "mic" : "magnifyingglass",
                    description: Text(
                        query.isEmpty
                            ? "Press \(GlobalShortcut.describe(keyCode: settings.shortcutKeyCode, modifiers: settings.shortcutModifiers)) anywhere to start dictating."
                            : "Nothing matches “\(query)”."
                    )
                )
            }
        }
        .frame(minWidth: 760, minHeight: 460)
    }

    private var sidebar: some View {
        List(filtered, selection: $selection) { note in
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if note.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }
                    Text(note.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(note.createdAt, format: .dateTime.month().day().hour().minute())
                    Text("·")
                    Text(durationString(note.duration))
                    if note.improvedText == nil {
                        Text("·")
                        Text("raw")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .tag(note.id)
            .contextMenu {
                Button("Copy") { Delivery.copyToClipboard(note.displayText) }
                Button(note.isFavorite ? "Remove from Favourites" : "Add to Favourites") {
                    note.isFavorite.toggle()
                    store.touch(note)
                }
                Divider()
                Button("Delete", role: .destructive) { store.delete(note) }
            }
        }
        .searchable(text: $query, placement: .sidebar, prompt: "Search notes")
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $showFavouritesOnly) {
                    Image(systemName: showFavouritesOnly ? "star.fill" : "star")
                }
                .help("Show favourites only")
            }
            ToolbarItem {
                Button {
                    controller.beginRecording()
                } label: {
                    Image(systemName: "mic.fill")
                }
                .help("Start recording")
            }
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
    }

    private func durationString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Detail

private struct NoteDetail: View {
    @Bindable var note: VoiceNote
    @ObservedObject var controller: AppController
    @ObservedObject var store: NoteStore
    @ObservedObject var settings: AppSettings

    @State private var showingRaw = false
    @State private var draft = ""
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            editor
            Divider()
            footer
        }
        .onAppear { draft = currentText }
        .onChange(of: showingRaw) { _, _ in draft = currentText }
        // Re-run rewrites the note underneath a draft that was seeded once, so
        // without this the editor goes on showing the old text — Re-run looks
        // like it did nothing, and the next keystroke writes the stale draft
        // back over the new improvement.
        .onChange(of: note.improvedText) { _, _ in syncDraft() }
        .onChange(of: note.rawTranscript) { _, _ in syncDraft() }
    }

    /// Pulls the note's text back into the editor, unless the editor already
    /// agrees — the note changing because the user is typing must not disturb
    /// the cursor.
    private func syncDraft() {
        if draft != currentText { draft = currentText }
    }

    private var currentText: String {
        showingRaw ? note.rawTranscript : note.displayText
    }

    private var header: some View {
        HStack(spacing: 10) {
            Picker("", selection: $showingRaw) {
                Text("Improved").tag(false)
                Text("Raw").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            .disabled(note.improvedText == nil)

            Spacer()

            Button {
                note.isFavorite.toggle()
                store.touch(note)
            } label: {
                Image(systemName: note.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(note.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help("Favourite")

            Menu {
                ForEach(settings.allModes) { mode in
                    Button(mode.name) { controller.reimprove(note, mode: mode) }
                }
            } label: {
                Label("Re-run", systemImage: "arrow.clockwise")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Improve again with a different mode")

            Button {
                Delivery.copyToClipboard(draft)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                store.delete(note)
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete note")
        }
        .padding(12)
    }

    private var editor: some View {
        TextEditor(text: $draft)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .padding(10)
            .onChange(of: draft) { _, newValue in
                // Edits write back to whichever version is on screen.
                if showingRaw {
                    note.rawTranscript = newValue
                } else {
                    note.improvedText = newValue
                }
                note.updatedAt = Date()
            }
            .onDisappear { store.save() }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(note.tags, id: \.self) { tag in
                    HStack(spacing: 3) {
                        Text(tag)
                        Button {
                            note.tags.removeAll { $0 == tag }
                            store.touch(note)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 7))
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 10))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                }

                TextField("Add tag", text: $newTag)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .frame(width: 80)
                    .onSubmit {
                        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty, !note.tags.contains(trimmed) else { return }
                        note.tags.append(trimmed)
                        store.touch(note)
                        newTag = ""
                    }
                Spacer()
            }

            HStack(spacing: 8) {
                Label(note.speechProvider, systemImage: "waveform")
                if let textProvider = note.textProvider {
                    Label(textProvider, systemImage: "wand.and.stars")
                }
                Label(note.mode, systemImage: "text.alignleft")
                Label(note.language, systemImage: "globe")
                if note.audioPath != nil {
                    Label("Audio kept", systemImage: "waveform.circle")
                }
                Spacer()
                Text(note.createdAt, format: .dateTime.year().month().day().hour().minute())
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}
