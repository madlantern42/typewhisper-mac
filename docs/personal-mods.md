# Personal Modifications

This fork adds three features on top of upstream TypeWhisper. Everything is
designed to be **additive and merge-friendly**: new logic lives in
`TypeWhisper/Personal/` and edits to upstream files are minimal and tagged with
`PERSONAL MODIFICATION` comments so they are easy to spot during a rebase.

## Keeping in sync with upstream

```
# one-time
git remote -v                       # origin = your fork, upstream = TypeWhisper/typewhisper-mac

# pull in upstream improvements
git fetch upstream
git checkout main && git merge upstream/main
git checkout personal && git rebase main
```

Conflicts only occur where upstream changes the exact lines we touched. The
tagged single-line hooks (below) keep that surface small.

## Files added (`TypeWhisper/Personal/`)

| File | Purpose |
|------|---------|
| `FuzzyTermMatcher.swift` | Levenshtein + phonetic key matcher (pure logic). |
| `DictionaryService+FuzzyTerms.swift` | Builds matcher from enabled terms; learns terms from review edits. |
| `ReviewLearning.swift` | Diffs raw vs. edited transcript → new terms to learn (pure). |
| `TranscriptReviewView.swift` | SwiftUI editor surface. |
| `TranscriptReviewController.swift` | NSPanel host + focus capture/restore + async `review()`. |
| `DictionarySyncModels.swift` | Codable sync wire format. |
| `DictionarySyncMerge.swift` | Pure union / last-writer-wins merge. |
| `DictionarySyncService.swift` | File IO, folder bookmark, file-watch, debounced export. |
| `PersonalSettingsSection.swift` | Settings UI for all three features. |

Tests: `TypeWhisperTests/{FuzzyTermMatcher,DictionarySyncMerge,ReviewLearning}Tests.swift`.

New files are registered into the Xcode project by
`scripts/add_personal_files.py` (the `xcodeproj` Ruby gem corrupts this
project on save because of a SwiftPM product, so we hand-edit `project.pbxproj`
with anchored, verified insertions).

## Upstream files touched (all tagged `PERSONAL MODIFICATION`)

- `App/UserDefaultsKeys.swift` — 4 new keys.
- `Models/DictionaryEntry.swift` — added `modifiedAt` (for sync merge).
- `Services/DictionaryService.swift` — `syncSnapshot()` / `applySyncedEntries()`; bump `modifiedAt` on edit/toggle.
- `Services/PostProcessingPipeline.swift` — one line: apply fuzzy matching after dictionary corrections.
- `App/ServiceContainer.swift` — construct + start `DictionarySyncService`.
- `Views/AdvancedSettingsView.swift` — one line: embed `PersonalSettingsSection()`.
- `ViewModels/DictationViewModel.swift` — review-before-insert branch in the insertion handoff.

## Feature 1 — Review before insert

When **Settings → Advanced → Review transcript before inserting** is on, each
dictation pops an editable window (`TranscriptReviewController`). The user fixes
mistakes; on **Insert** the edited text is pasted into the original target app
(focus is captured before showing and restored before pasting), and any new
proper nouns introduced are learned as dictionary **terms**
(`ReviewLearning.newTerms`). **Cancel** inserts nothing.

## Feature 2 — Fuzzy / phonetic term matching

Whisper mis-transcribes out-of-vocabulary names differently every time
("suprabase", "superbase", "supabayse"). Exact find/replace can't keep up, so:

1. Protected **terms** prime Whisper's prompt (existing behaviour) — fixes most
   cases at the source.
2. `FuzzyTermMatcher` maps residual near-variants to the canonical term using
   edit distance + a phonetic key, generalizing to *unseen* misspellings. It is
   conservative (min length, same first letter, ambiguity guard) to avoid
   rewriting legitimate words.

Runs in the post-processing pipeline right after dictionary corrections.

## Feature 3 — Cross-machine dictionary sync (no CloudKit)

CloudKit's private DB is per-Apple-ID, and the machines use **different** Apple
IDs, so sync goes through a JSON file in a **cloud-drive folder** (Google Drive,
Dropbox, …) which is account-based, not Apple-ID-based.

- Pick the folder in Settings → Advanced → *Choose Sync Folder…*.
- The dictionary is exported to `dictionary-sync.json` (debounced) on change.
- A directory watcher merges remote changes (`DictionarySyncMerge`:
  union, last-writer-wins by `modifiedAt`) and writes the union back.
- The SQLite store is **not** synced directly (corruption-prone in cloud
  folders) — only the export file is.

**Known limitation:** deletions are not propagated (no tombstones). An entry
deleted on one machine can reappear from another's file and must be deleted
again. A dictionary mostly grows, so this is an accepted trade-off.
