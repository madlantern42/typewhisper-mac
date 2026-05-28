//  DictionarySyncService.swift
//  TypeWhisper — PERSONAL MODIFICATION
//
//  Syncs the dictionary across machines through a single JSON file placed in a
//  cloud-drive folder (Google Drive / Dropbox / OneDrive). Cloud drives are
//  account-based, not Apple-ID-based, so this works across Macs signed into
//  different Apple IDs — unlike CloudKit.
//
//  Design:
//   • The SQLite store is NOT synced directly (corruption-prone in cloud
//     folders). We sync a small export file: `dictionary-sync.json`.
//   • On local dictionary change -> debounced export (union written back).
//   • On remote file change -> read + merge (last-writer-wins by modifiedAt) ->
//     apply newer remote entries locally, then write the union back.
//   • Self-writes are suppressed by remembering the last bytes we wrote.

import Foundation
import Combine
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "TypeWhisper", category: "DictionarySyncService")

@MainActor
final class DictionarySyncService: ObservableObject {
    private let dictionaryService: DictionaryService

    @Published private(set) var isActive = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var lastError: String?

    private var folderURL: URL?
    private var accessingScopedResource = false
    private var dirSource: DispatchSourceFileSystemObject?
    private var cancellables = Set<AnyCancellable>()

    private var exportDebounce: Task<Void, Never>?
    private var lastWrittenData: Data?
    /// Guards against the export->file-change->import feedback loop.
    private var isApplyingRemote = false

    private let fileName = "dictionary-sync.json"
    private let deviceName = Host.current().localizedName ?? "Mac"

    init(dictionaryService: DictionaryService) {
        self.dictionaryService = dictionaryService
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.dictionarySyncEnabled)
    }

    // MARK: - Lifecycle

    /// Starts syncing if enabled and a folder bookmark is configured.
    func startIfConfigured() {
        guard isEnabled else { return }
        guard let url = resolveFolderBookmark() else {
            lastError = "Sync folder is not configured."
            return
        }
        start(folderURL: url)
    }

    /// Persists the chosen folder and (re)starts syncing.
    func configureFolder(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: UserDefaultsKeys.dictionarySyncFolderBookmark)
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.dictionarySyncEnabled)
            stop()
            start(folderURL: url)
        } catch {
            lastError = "Could not bookmark folder: \(error.localizedDescription)"
            logger.error("Bookmark failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        exportDebounce?.cancel()
        dirSource?.cancel()
        dirSource = nil
        cancellables.removeAll()
        if accessingScopedResource {
            folderURL?.stopAccessingSecurityScopedResource()
            accessingScopedResource = false
        }
        folderURL = nil
        isActive = false
    }

    private func start(folderURL: URL) {
        self.folderURL = folderURL
        accessingScopedResource = folderURL.startAccessingSecurityScopedResource()
        isActive = true
        lastError = nil

        // Initial reconcile: pull remote, then push union.
        importAndMerge()
        scheduleExport()
        observeLocalChanges()
        startWatching(folderURL: folderURL)
    }

    // MARK: - Bookmark resolution

    private func resolveFolderBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.dictionarySyncFolderBookmark) else {
            return nil
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return url
    }

    private var fileURL: URL? {
        folderURL?.appendingPathComponent(fileName)
    }

    // MARK: - Local change observation

    private func observeLocalChanges() {
        // `entries` is private(set) so its publisher isn't visible here; observe
        // the ObservableObject's change signal instead (fires when entries change).
        dictionaryService.objectWillChange
            .sink { [weak self] _ in
                guard let self, !self.isApplyingRemote else { return }
                self.scheduleExport()
            }
            .store(in: &cancellables)
    }

    private func scheduleExport() {
        exportDebounce?.cancel()
        exportDebounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, !Task.isCancelled else { return }
            self.exportNow()
        }
    }

    // MARK: - Export

    private func exportNow() {
        guard let fileURL else { return }
        let doc = SyncDocument(
            version: SyncDocument.currentVersion,
            deviceName: deviceName,
            updatedAt: Date(),
            entries: dictionaryService.syncSnapshot()
        )
        do {
            let data = try SyncDocument.encoder().encode(doc)
            // Skip if identical to what's already there (avoid churn).
            if data == lastWrittenData { return }
            try data.write(to: fileURL, options: .atomic)
            lastWrittenData = data
            lastSyncDate = Date()
        } catch {
            lastError = error.localizedDescription
            logger.error("Export failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Import + merge

    private func importAndMerge() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            // Ignore our own write echoed back by the watcher.
            if data == lastWrittenData { return }

            let remoteDoc = try SyncDocument.decoder().decode(SyncDocument.self, from: data)
            let local = dictionaryService.syncSnapshot()
            let result = DictionarySyncMerge.merge(local: local, remote: remoteDoc.entries)

            if !result.toApplyLocally.isEmpty {
                isApplyingRemote = true
                dictionaryService.applySyncedEntries(result.toApplyLocally)
                isApplyingRemote = false
            }

            // Write the union back so our additions reach other machines.
            let mergedDoc = SyncDocument(
                version: SyncDocument.currentVersion,
                deviceName: deviceName,
                updatedAt: Date(),
                entries: result.mergedDocument
            )
            let mergedData = try SyncDocument.encoder().encode(mergedDoc)
            if mergedData != data {
                try mergedData.write(to: fileURL, options: .atomic)
            }
            lastWrittenData = mergedData
            lastSyncDate = Date()
        } catch {
            lastError = error.localizedDescription
            logger.error("Import/merge failed: \(error.localizedDescription)")
        }
    }

    // MARK: - File watching

    /// Watches the *directory* (cloud drives replace files atomically, which
    /// would invalidate a descriptor opened on the file itself).
    private func startWatching(folderURL: URL) {
        let fd = open(folderURL.path, O_EVTONLY)
        guard fd >= 0 else {
            logger.error("Could not open folder for watching: \(folderURL.path)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .utility)
        )
        var debounceWorkItem: DispatchWorkItem?
        source.setEventHandler { [weak self] in
            debounceWorkItem?.cancel()
            let work = DispatchWorkItem {
                Task { @MainActor in self?.importAndMerge() }
            }
            debounceWorkItem = work
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.6, execute: work)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        dirSource = source
    }
}
