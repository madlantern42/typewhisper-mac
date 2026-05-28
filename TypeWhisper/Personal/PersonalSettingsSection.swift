//  PersonalSettingsSection.swift
//  TypeWhisper — PERSONAL MODIFICATION
//
//  Settings UI for the three fork features. Embedded into AdvancedSettingsView
//  with a single line so the upstream view stays almost untouched.

import SwiftUI
import AppKit

struct PersonalSettingsSection: View {
    @ObservedObject private var syncService = ServiceContainer.shared.dictionarySyncService

    @AppStorage(UserDefaultsKeys.fuzzyTermMatchingEnabled) private var fuzzyEnabled: Bool = true
    @AppStorage(UserDefaultsKeys.reviewBeforeInsert) private var reviewBeforeInsert: Bool = false
    @AppStorage(UserDefaultsKeys.dictionarySyncEnabled) private var syncEnabled: Bool = false

    var body: some View {
        Section("Personal · Smart Dictation") {
            Toggle("Review transcript before inserting", isOn: $reviewBeforeInsert)
            Text("Shows an editable window after each dictation. Your edits are inserted into the target app, and corrections are learned into the dictionary.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Fuzzy-match misheard terms", isOn: $fuzzyEnabled)
            Text("Maps near-variants of your protected dictionary terms to the correct spelling (e.g. \u{201C}suprabase\u{201D} \u{2192} \u{201C}Supabase\u{201D}).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Personal · Dictionary Sync") {
            Toggle("Sync dictionary across machines", isOn: Binding(
                get: { syncEnabled },
                set: { newValue in
                    syncEnabled = newValue
                    if newValue {
                        syncService.startIfConfigured()
                    } else {
                        syncService.stop()
                    }
                }
            ))
            Text("Syncs terms and corrections through a JSON file in a cloud-drive folder (Google Drive, Dropbox, \u{2026}). Works across Apple IDs.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Choose Sync Folder\u{2026}") { chooseFolder() }
                if syncService.isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            if let date = syncService.lastSyncDate {
                Text("Last sync: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = syncService.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a cloud-drive folder to store dictionary-sync.json")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        syncService.configureFolder(url)
    }
}
