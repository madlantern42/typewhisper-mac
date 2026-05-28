# Working on this repository

**This is a personal fork of TypeWhisper.** Before doing anything, read
[`docs/personal-mods.md`](docs/personal-mods.md) — it documents the three
fork features, the fork-sync workflow with `upstream`, and (importantly)
operational traps that will bite you if you do not know about them.

## TL;DR

- The active branch for development is **`personal`** (not `main`).
- `main` is a clean mirror of `upstream/main`
  (`https://github.com/TypeWhisper/typewhisper-mac`). To pull upstream changes:

      git fetch upstream
      git checkout main && git merge upstream/main
      git checkout personal && git rebase main

- All fork-added logic lives in `TypeWhisper/Personal/`.
- Every edit to an *upstream* file is tagged with the comment
  `PERSONAL MODIFICATION`. To enumerate the entire upstream surface during a
  rebase: `git grep "PERSONAL MODIFICATION"`.

## Traps you would otherwise hit

- **Do not use the `xcodeproj` Ruby gem** to modify the project — its `save`
  corrupts this project (the MLXVLM SwiftPM product breaks the gem's
  serializer). To add a new file to the build, edit
  `scripts/add_personal_files.py` and run it. Details in
  `docs/personal-mods.md` § Maintenance notes.

- The project uses **explicit file references** (no synchronized groups).
  Dropping a `.swift` file into a folder does **not** add it to the build.

- The build command needs to disable code signing for headless builds:

      xcodebuild build -project TypeWhisper.xcodeproj -scheme TypeWhisper \
        -configuration Debug -destination 'platform=macOS' \
        CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

## Design rationale lives in `docs/personal-mods.md`

That file covers the three features (review-before-insert, fuzzy/phonetic
term matching, cross-machine dictionary sync via cloud-drive JSON), the
deliberate trade-offs (no tombstones, uppercase requirement in
ReviewLearning, conservative fuzzy thresholds), and the deferred work
(LLM Layer 3, snippets sync, tombstones). Read it before changing any
fork code.
