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

---

## Maintenance notes

### Adding a new file to `TypeWhisper/Personal/`
The Xcode project uses explicit file references (no synchronized groups), so a
new file on disk is invisible to the build until it is registered. **Do not use
the `xcodeproj` Ruby gem** — its `save` corrupts this project on the
`MLXVLM` SwiftPM product (the gem cannot serialize a build file whose product
reference has no parent group, and silently writes a damaged pbxproj). Use the
hand-edit script instead:

```bash
# 1. Add the file path(s) to APP_FILES or TEST_FILES in scripts/add_personal_files.py
# 2. Run:
python3 scripts/add_personal_files.py
# 3. Verify:
plutil -lint TypeWhisper.xcodeproj/project.pbxproj
```

The script is idempotent and uses anchored single-occurrence replacements; it
will refuse to run if the file is already registered.

### Build + test commands
```bash
# Build
xcodebuild build -project TypeWhisper.xcodeproj -scheme TypeWhisper \
  -configuration Debug -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

# Just the new tests
xcodebuild test -project TypeWhisper.xcodeproj -scheme TypeWhisper \
  -destination 'platform=macOS' \
  -only-testing:TypeWhisperTests/FuzzyTermMatcherTests \
  -only-testing:TypeWhisperTests/DictionarySyncMergeTests \
  -only-testing:TypeWhisperTests/ReviewLearningTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

### Convention
Every edit to an upstream file is tagged with the comment
`PERSONAL MODIFICATION`. During a rebase, `git grep "PERSONAL MODIFICATION"`
gives the exhaustive list of touch points.

---

## Known issues / future work

### Review window — focus restoration
`TranscriptReviewController.finish(with:)` reactivates the captured target app
and waits **150 ms** before resuming the continuation that triggers the paste.
That delay is the knob to turn if paste ever lands in the wrong app on a slow
machine — try 250–400 ms. The capture point is
`NSWorkspace.shared.frontmostApplication` at the moment `review()` is called,
which is *before* `NSApp.activate` is invoked, so it should always be the user's
intended target. Has not been GUI-tested across edge cases (Spaces switches,
fullscreen apps).

### Fuzzy matcher — false-positive tuning
`FuzzyTermMatcher` defaults: `minLength: 5`, `maxDistanceRatio: 0.34`,
`requireSameFirstLetter: true`, plus an ambiguity guard that rejects ties.
If users report unwanted rewrites:
- raise `minLength`
- lower `maxDistanceRatio` (stricter)
- keep `requireSameFirstLetter` on (it is the strongest guard)
- consider an English-dictionary check (skip fuzzy if token *is* a real word).

Settings UI for these knobs is not wired; they are constructor parameters.

### ReviewLearning — uppercase requirement
Only words containing at least one uppercase letter are learned as terms. This
filters common-word swaps ("again", "today") and matches the actual product
intent (learn brand / proper names). If users want lowercase technical jargon
("transformer") learned too, drop the `isUppercase` guard in
`ReviewLearning.newTerms` and add a different filter (e.g. a stopword list).

### Sync — tombstones
The current design propagates additions and edits but **not deletions**. If
deletion propagation becomes important, the path is: add a `Deletion` SwiftData
model with `(id, deletedAt)`, write tombstones into the sync file, and have
`applySyncedEntries` honor incoming tombstones by deleting (and re-writing the
tombstone forward). Adds enough complexity that it was deferred.

### Sync — multi-folder / per-feature
Snippets are also user personalization but not synced. Same pattern would
apply (`snippets-sync.json` in the same folder). Watch out for the
`snippets.store` location and the existing `SnippetService` API surface.

### LLM cleanup pass (deferred Layer 3)
The original design discussion called out a third layer: feed a few-shot of
`(raw, edited)` pairs to the existing LLM post-processing step so it
generalizes stylistic corrections beyond what dictionary + fuzzy can catch.
Not implemented — would require capturing review pairs and threading them
into the prompt that `PostProcessingPipeline` priority-300 step constructs.

### Settings UI surface
All three personal toggles live in **Settings → Advanced** as injected
sections at the top of `AdvancedSettingsView`. If you ever want a dedicated
tab, the wire-up points are in `TypeWhisper/Views/SettingsView.swift`:
`SettingsTab` enum + `settingsDetail(for:)` switch + the destinations array.
That's a bigger upstream surface and was avoided on purpose.
