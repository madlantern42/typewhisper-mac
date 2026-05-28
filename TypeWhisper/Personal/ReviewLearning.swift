//  ReviewLearning.swift
//  TypeWhisper — PERSONAL MODIFICATION
//
//  Derives what to learn from the diff between the raw transcript and the
//  user's edited version (captured by the review window).
//
//  Philosophy (from the design discussion): we don't try to learn every
//  one-off correction as a literal find/replace. Instead we surface *new
//  words* the user introduced — typically proper nouns / jargon Whisper got
//  wrong — and add them as protected dictionary **terms**. Those then:
//    1. bias Whisper's prompt so the word is transcribed correctly next time, and
//    2. feed the fuzzy matcher so unseen mis-hearings map to the canonical form.
//
//  Pure and dependency-free so it is fully unit-testable.

import Foundation

enum ReviewLearning {
    /// Minimum length for a learned term (avoids noise from short words).
    static let minTermLength = 4

    /// Words present in `edited` but absent from `original` (case-insensitive),
    /// restricted to "word-like" tokens of sufficient length. Preserves the
    /// edited capitalization (so "Supabase" is learned, not "supabase").
    static func newTerms(original: String, edited: String) -> [String] {
        let originalWords = Set(tokenize(original).map { $0.lowercased() })
        var seen = Set<String>()
        var result: [String] = []

        for word in tokenize(edited) {
            let lower = word.lowercased()
            guard word.count >= minTermLength else { continue }
            guard isWordLike(word) else { continue }
            // Proper-noun heuristic: require at least one uppercase letter.
            // Filters common-word swaps ("again", "today", ...) and keeps the
            // brand / jargon names that actually generalize ("Supabase", ...).
            guard word.contains(where: { $0.isUppercase }) else { continue }
            guard !originalWords.contains(lower) else { continue }
            guard !seen.contains(lower) else { continue }
            seen.insert(lower)
            result.append(word)
        }
        return result
    }

    /// Splits text into word tokens (letters/digits/intra-word apostrophes).
    static func tokenize(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for ch in text {
            if ch.isLetter || ch.isNumber || ch == "'" {
                current.append(ch)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// A token is "word-like" if it is mostly alphabetic (rejects pure numbers
    /// and timestamps). Mixed-case or capitalized words pass — good signal for
    /// proper nouns and brand names.
    static func isWordLike(_ word: String) -> Bool {
        let letters = word.filter { $0.isLetter }.count
        return letters >= max(2, word.count - 2)
    }
}
