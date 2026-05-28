#!/usr/bin/env ruby
# PERSONAL MODIFICATION: registers fork-added source files into the Xcode
# project (the project uses explicit file references, not synchronized groups).
# Idempotent — running it twice will not create duplicate references.

require "xcodeproj"

# Workaround: this project references a SwiftPM product (MLXVLM) in build
# phases in a way that trips xcodeproj's annotation during save. The annotation
# is only a human-readable comment, so tolerate failures.
module Xcodeproj
  class Project
    module Object
      class PBXBuildFile
        def ascii_plist_annotation
          " /* #{display_name} */ "
        rescue StandardError
          " "
        end
      end
    end
  end
end

project_path = "TypeWhisper.xcodeproj"
project = Xcodeproj::Project.open(project_path)

main_target = project.targets.find { |t| t.name == "TypeWhisper" }
test_target = project.targets.find { |t| t.name == "TypeWhisperTests" }
abort("Missing targets") unless main_target && test_target

# Files: [relative_path_on_disk, target, group_path_segments]
app_files = [
  "TypeWhisper/Personal/FuzzyTermMatcher.swift",
  "TypeWhisper/Personal/DictionaryService+FuzzyTerms.swift",
  "TypeWhisper/Personal/DictionarySyncModels.swift",
  "TypeWhisper/Personal/DictionarySyncMerge.swift",
  "TypeWhisper/Personal/DictionarySyncService.swift",
  "TypeWhisper/Personal/PersonalSettingsSection.swift",
  "TypeWhisper/Personal/ReviewLearning.swift",
  "TypeWhisper/Personal/TranscriptReviewView.swift",
  "TypeWhisper/Personal/TranscriptReviewController.swift",
]

test_files = [
  "TypeWhisperTests/FuzzyTermMatcherTests.swift",
  "TypeWhisperTests/DictionarySyncMergeTests.swift",
  "TypeWhisperTests/ReviewLearningTests.swift",
]

def find_or_create_group(project, segments)
  group = project.main_group
  segments.each do |seg|
    existing = group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == seg }
    group = existing || group.new_group(seg, seg)
  end
  group
end

def already_referenced?(project, path)
  project.files.any? { |f| f.real_path.to_s.end_with?(path) }
end

added = 0

app_files.each do |path|
  if already_referenced?(project, path)
    puts "skip (exists): #{path}"
    next
  end
  segments = File.dirname(path).split("/")
  group = find_or_create_group(project, segments)
  ref = group.new_reference(File.basename(path))
  main_target.add_file_references([ref])
  added += 1
  puts "added (app): #{path}"
end

test_files.each do |path|
  if already_referenced?(project, path)
    puts "skip (exists): #{path}"
    next
  end
  segments = File.dirname(path).split("/")
  group = find_or_create_group(project, segments)
  ref = group.new_reference(File.basename(path))
  test_target.add_file_references([ref])
  added += 1
  puts "added (test): #{path}"
end

project.save
puts "Done. #{added} file(s) added."
