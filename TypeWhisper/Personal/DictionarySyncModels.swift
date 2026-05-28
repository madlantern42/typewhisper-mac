//  DictionarySyncModels.swift
//  TypeWhisper — PERSONAL MODIFICATION
//
//  Codable representation of dictionary entries for the cross-machine sync
//  file (dictionary-sync.json placed in a cloud-drive folder). This is a
//  separate, richer format than the user-facing DictionaryExporter JSON
//  because sync needs a stable `id` and `modifiedAt` to merge safely.

import Foundation

/// One dictionary entry as stored in the sync file.
struct SyncEntry: Codable, Equatable {
    var id: UUID
    var type: String          // "term" | "correction"
    var original: String
    var replacement: String?
    var caseSensitive: Bool
    var isEnabled: Bool
    var modifiedAt: Date
}

/// Top-level sync document.
struct SyncDocument: Codable {
    var version: Int
    var deviceName: String
    var updatedAt: Date
    var entries: [SyncEntry]

    static let currentVersion = 1

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
