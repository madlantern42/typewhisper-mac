#!/usr/bin/env python3
"""PERSONAL MODIFICATION: register fork-added Swift files into the Xcode project.

The xcodeproj Ruby gem corrupts this project on save (a SwiftPM product,
MLXVLM, trips its serializer), so we hand-edit project.pbxproj with targeted,
verified insertions that mirror the project's AA/BB id convention.
Idempotent: refuses to run if the markers are already present.
"""
import sys

PBX = "TypeWhisper.xcodeproj/project.pbxproj"

APP_FILES = [
    "FuzzyTermMatcher.swift",
    "DictionaryService+FuzzyTerms.swift",
    "DictionarySyncModels.swift",
    "DictionarySyncMerge.swift",
    "DictionarySyncService.swift",
    "PersonalSettingsSection.swift",
    "ReviewLearning.swift",
    "TranscriptReviewView.swift",
    "TranscriptReviewController.swift",
]
TEST_FILES = [
    "FuzzyTermMatcherTests.swift",
    "DictionarySyncMergeTests.swift",
    "ReviewLearningTests.swift",
]

def gid(prefix, n):
    return prefix + str(n).zfill(20)  # 22-char id, matches existing convention

def main():
    with open(PBX, "r") as f:
        text = f.read()

    if "Personal/FuzzyTermMatcher.swift" in text:
        print("Already registered; nothing to do.")
        return 0

    build_lines = []      # PBXBuildFile section
    fileref_lines = []     # PBXFileReference section
    app_group_children = []
    test_group_children = []
    app_sources = []
    test_sources = []

    def emit(basename, relpath, build_id, ref_id, is_test):
        build_lines.append(
            f'\t\t{build_id} /* {basename} in Sources */ = '
            f'{{isa = PBXBuildFile; fileRef = {ref_id} /* {basename} */; }};'
        )
        fileref_lines.append(
            f'\t\t{ref_id} /* {basename} */ = {{isa = PBXFileReference; '
            f'lastKnownFileType = sourcecode.swift; path = "{relpath}"; '
            f'sourceTree = SOURCE_ROOT; }};'
        )
        child = f'\t\t\t\t{ref_id} /* {basename} */,'
        src = f'\t\t\t\t{build_id} /* {basename} in Sources */,'
        if is_test:
            test_group_children.append(child)
            test_sources.append(src)
        else:
            app_group_children.append(child)
            app_sources.append(src)

    n = 9001
    for name in APP_FILES:
        emit(name, f"TypeWhisper/Personal/{name}", gid("AA", n), gid("BB", n), False)
        n += 1
    n = 9101
    for name in TEST_FILES:
        emit(name, f"TypeWhisperTests/{name}", gid("AA", n), gid("BB", n), True)
        n += 1

    # Anchored, single-occurrence replacements.
    edits = [
        ("/* End PBXBuildFile section */",
         "\n".join(build_lines) + "\n/* End PBXBuildFile section */"),
        ("/* End PBXFileReference section */",
         "\n".join(fileref_lines) + "\n/* End PBXFileReference section */"),
        ("\t\t\t\tBB00000000000000000079 /* DictionaryService.swift */,",
         "\t\t\t\tBB00000000000000000079 /* DictionaryService.swift */,\n" + "\n".join(app_group_children)),
        ("\t\t\t\tA8D4F2B6E1C3097B5F8A4E62 /* DictionaryExporterTests.swift */,",
         "\t\t\t\tA8D4F2B6E1C3097B5F8A4E62 /* DictionaryExporterTests.swift */,\n" + "\n".join(test_group_children)),
        ("\t\t\t\tAA00000000000000000079 /* DictionaryService.swift in Sources */,",
         "\t\t\t\tAA00000000000000000079 /* DictionaryService.swift in Sources */,\n" + "\n".join(app_sources)),
        ("\t\t\t\tC7A3E9F1D5B2084A6E9C3D71 /* DictionaryExporterTests.swift in Sources */,",
         "\t\t\t\tC7A3E9F1D5B2084A6E9C3D71 /* DictionaryExporterTests.swift in Sources */,\n" + "\n".join(test_sources)),
    ]

    for anchor, replacement in edits:
        count = text.count(anchor)
        if count != 1:
            print(f"ERROR: anchor found {count} times (expected 1): {anchor[:60]!r}")
            return 1
        text = text.replace(anchor, replacement, 1)

    with open(PBX, "w") as f:
        f.write(text)
    print(f"OK: registered {len(APP_FILES)} app + {len(TEST_FILES)} test files.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
