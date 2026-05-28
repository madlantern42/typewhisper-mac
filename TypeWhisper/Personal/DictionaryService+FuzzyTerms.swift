//  DictionaryService+FuzzyTerms.swift
//  TypeWhisper — PERSONAL MODIFICATION
//
//  Adds fuzzy/phonetic protected-term matching on top of the existing
//  dictionary. Lives in an extension so the upstream DictionaryService.swift
//  stays untouched (keeps the personal fork merge-friendly).

import Foundation

@MainActor
extension DictionaryService {
    /// Whether fuzzy term matching is enabled (defaults to on).
    var fuzzyTermMatchingEnabled: Bool {
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.fuzzyTermMatchingEnabled) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: UserDefaultsKeys.fuzzyTermMatchingEnabled)
    }

    /// Builds a matcher from the currently enabled dictionary *terms*
    /// (the canonical proper nouns / jargon the user wants protected).
    func makeFuzzyTermMatcher() -> FuzzyTermMatcher {
        FuzzyTermMatcher(canonicalTerms: terms.map(\.original))
    }

    /// Applies fuzzy matching of near-variants to protected terms.
    /// No-op when disabled or when there are no terms.
    func applyFuzzyTermMatching(to text: String) -> String {
        guard fuzzyTermMatchingEnabled else { return text }
        let matcher = makeFuzzyTermMatcher()
        guard !matcher.isEmpty else { return text }
        return matcher.apply(to: text)
    }

    /// Learns new proper nouns / jargon introduced by the user in the review
    /// window, adding them as protected terms (deduped by `addEntry`).
    func learnTermsFromReview(original: String, edited: String) {
        for term in ReviewLearning.newTerms(original: original, edited: edited) {
            addEntry(type: .term, original: term)
        }
    }
}
