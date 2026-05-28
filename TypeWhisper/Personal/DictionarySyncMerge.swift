//  DictionarySyncMerge.swift
//  TypeWhisper — PERSONAL MODIFICATION
//
//  Pure, dependency-free merge logic for cross-machine dictionary sync.
//  Kept separate from file IO so it is fully unit-testable.
//
//  Strategy: union by `id`, last-writer-wins by `modifiedAt`. On a timestamp
//  tie the local copy is kept (deterministic). Deletions are NOT propagated —
//  a dictionary mostly grows, and tombstone tracking would add significant
//  complexity; an entry deleted on one machine can reappear from another's
//  file and must be deleted again. This is a deliberate, documented trade-off.

import Foundation

enum DictionarySyncMerge {
    struct Result: Equatable {
        /// Remote entries that should be upserted into the local store
        /// (new ids, or newer modifiedAt than the local copy).
        var toApplyLocally: [SyncEntry]
        /// The full merged set to write back to the sync file so that every
        /// machine's additions propagate to the others.
        var mergedDocument: [SyncEntry]
    }

    /// - Parameters:
    ///   - local: the current local entries.
    ///   - remote: entries read from the sync file (may be empty / missing).
    static func merge(local: [SyncEntry], remote: [SyncEntry]) -> Result {
        var byID: [UUID: SyncEntry] = [:]
        for entry in local { byID[entry.id] = entry }

        var toApply: [SyncEntry] = []

        for remoteEntry in remote {
            if let localEntry = byID[remoteEntry.id] {
                // Same entry on both sides — newer wins.
                if remoteEntry.modifiedAt > localEntry.modifiedAt {
                    byID[remoteEntry.id] = remoteEntry
                    toApply.append(remoteEntry)
                }
                // else: local is newer or tie -> keep local, nothing to apply.
            } else {
                // New entry we have never seen.
                byID[remoteEntry.id] = remoteEntry
                toApply.append(remoteEntry)
            }
        }

        let merged = byID.values.sorted { lhs, rhs in
            if lhs.type != rhs.type { return lhs.type < rhs.type }
            return lhs.original.lowercased() < rhs.original.lowercased()
        }

        return Result(toApplyLocally: toApply, mergedDocument: merged)
    }
}
