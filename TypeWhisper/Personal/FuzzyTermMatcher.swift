//  FuzzyTermMatcher.swift
//  TypeWhisper — PERSONAL MODIFICATION
//
//  Maps near-variants of user-protected canonical terms to their correct form.
//  Solves the many-to-one problem for proper nouns / jargon that Whisper
//  mis-transcribes differently each time (e.g. "suprabase", "superbase",
//  "supabayse" -> "Supabase") without having to enumerate every misspelling.
//
//  Pure value type with no app dependencies so it is fully unit-testable and
//  isolated from upstream files (keeps the personal fork merge-friendly).

import Foundation

/// Levenshtein edit distance between two strings (case handled by caller).
enum Levenshtein {
    static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,       // deletion
                    current[j - 1] + 1,    // insertion
                    previous[j - 1] + cost // substitution
                )
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    static func distance(_ a: String, _ b: String) -> Int {
        distance(Array(a), Array(b))
    }
}

/// A lightweight, deterministic phonetic key (Soundex-flavoured). Used as a
/// cheap booster alongside edit distance — words that sound alike collapse to
/// the same key. Not a full Double Metaphone, but enough to catch the common
/// vowel/consonant swaps Whisper produces.
enum PhoneticKey {
    private static let codes: [Character: Character] = [
        "b": "1", "f": "1", "p": "1", "v": "1",
        "c": "2", "g": "2", "j": "2", "k": "2", "q": "2", "s": "2", "x": "2", "z": "2",
        "d": "3", "t": "3",
        "l": "4",
        "m": "5", "n": "5",
        "r": "6"
    ]

    /// Returns a phonetic key. Empty for empty/non-alphabetic input.
    static func of(_ raw: String) -> String {
        let chars = Array(raw.lowercased().filter { $0.isLetter && $0.isASCII })
        guard let first = chars.first else { return "" }

        var result = String(first)
        var lastCode = codes[first]

        for ch in chars.dropFirst() {
            let code = codes[ch]
            if let code, code != lastCode {
                result.append(code)
            }
            // Vowels (and h/w/y) reset the "last code" so that a repeated
            // consonant separated by a vowel is not collapsed.
            if code == nil {
                lastCode = nil
            } else {
                lastCode = code
            }
        }
        return result
    }
}

/// Matches transcription tokens against a curated list of protected terms.
struct FuzzyTermMatcher {
    struct ProtectedTerm {
        let canonical: String      // the correct output form, e.g. "Supabase"
        let folded: String         // lowercased comparison form
        let phonetic: String

        init(canonical: String) {
            self.canonical = canonical
            self.folded = canonical.lowercased()
            self.phonetic = PhoneticKey.of(canonical)
        }
    }

    let terms: [ProtectedTerm]

    /// Minimum token length eligible for fuzzy matching. Short tokens are too
    /// collision-prone, so they only match exactly.
    let minLength: Int

    /// Maximum edit distance allowed, expressed as a fraction of the canonical
    /// term length (rounded down, floored at 1). 0.34 ≈ one third.
    let maxDistanceRatio: Double

    /// Require the first letter to match the canonical term. Strong heuristic
    /// for proper nouns that sharply reduces false positives
    /// (e.g. "database" will not be rewritten to "Supabase").
    let requireSameFirstLetter: Bool

    init(
        canonicalTerms: [String],
        minLength: Int = 5,
        maxDistanceRatio: Double = 0.34,
        requireSameFirstLetter: Bool = true
    ) {
        self.terms = canonicalTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(ProtectedTerm.init)
        self.minLength = minLength
        self.maxDistanceRatio = maxDistanceRatio
        self.requireSameFirstLetter = requireSameFirstLetter
    }

    var isEmpty: Bool { terms.isEmpty }

    /// Returns the canonical form for a single token, or nil if no confident
    /// match. Returns nil when the token already equals a canonical term
    /// (nothing to fix).
    func canonical(for token: String) -> String? {
        guard !terms.isEmpty else { return nil }
        let folded = token.lowercased()
        guard folded.count >= 2 else { return nil }

        // Exact-case match to a canonical => already correct, leave alone.
        // Folded match with different casing => return canonical (a casing fix
        // — Whisper often lowercases proper nouns).
        for term in terms {
            if term.folded == folded {
                return term.canonical == token ? nil : term.canonical
            }
        }

        let tokenPhonetic = PhoneticKey.of(token)
        let tokenFirst = folded.first

        var best: (term: ProtectedTerm, distance: Int)?
        var runnerUpDistance: Int?

        for term in terms {
            if requireSameFirstLetter, term.folded.first != tokenFirst { continue }
            if max(term.folded.count, folded.count) < minLength { continue }

            let dist = Levenshtein.distance(folded, term.folded)
            let allowed = max(1, Int(Double(term.folded.count) * maxDistanceRatio))
            let phoneticMatch = !tokenPhonetic.isEmpty && tokenPhonetic == term.phonetic

            // Accept on edit distance, OR phonetic match with a looser cap.
            let accepted = dist <= allowed || (phoneticMatch && dist <= allowed + 1)
            guard accepted else { continue }

            if best == nil || dist < best!.distance {
                runnerUpDistance = best?.distance
                best = (term, dist)
            } else if runnerUpDistance == nil || dist < runnerUpDistance! {
                runnerUpDistance = dist
            }
        }

        guard let best else { return nil }

        // Ambiguity guard: if two terms are equally close, do not guess.
        if let runnerUp = runnerUpDistance, runnerUp == best.distance { return nil }

        return best.term.canonical
    }

    /// Applies fuzzy matching across all word tokens in `text`, preserving
    /// surrounding punctuation and whitespace. Non-word runs are passed through
    /// untouched.
    func apply(to text: String) -> String {
        guard !terms.isEmpty, !text.isEmpty else { return text }

        var output = ""
        output.reserveCapacity(text.count)
        var wordBuffer = ""

        func flushWord() {
            guard !wordBuffer.isEmpty else { return }
            if let replacement = canonical(for: wordBuffer) {
                output += replacement
            } else {
                output += wordBuffer
            }
            wordBuffer.removeAll(keepingCapacity: true)
        }

        for ch in text {
            // Treat letters, digits and intra-word apostrophes as word chars.
            if ch.isLetter || ch.isNumber {
                wordBuffer.append(ch)
            } else {
                flushWord()
                output.append(ch)
            }
        }
        flushWord()
        return output
    }
}
