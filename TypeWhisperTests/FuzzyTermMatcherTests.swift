import XCTest
@testable import TypeWhisper

final class FuzzyTermMatcherTests: XCTestCase {

    // MARK: - Levenshtein

    func testLevenshteinBasics() {
        XCTAssertEqual(Levenshtein.distance("", ""), 0)
        XCTAssertEqual(Levenshtein.distance("abc", ""), 3)
        XCTAssertEqual(Levenshtein.distance("supabase", "suprabase"), 1) // insert r
        XCTAssertEqual(Levenshtein.distance("kitten", "sitting"), 3)
    }

    // MARK: - Phonetic key

    func testPhoneticKeyGroupsSimilarSounds() {
        // Same leading letter + similar consonant skeleton should collide.
        XCTAssertEqual(PhoneticKey.of("supabase"), PhoneticKey.of("supabayse"))
        XCTAssertFalse(PhoneticKey.of("supabase").isEmpty)
        XCTAssertEqual(PhoneticKey.of(""), "")
        XCTAssertEqual(PhoneticKey.of("123"), "")
    }

    // MARK: - Many-to-one canonicalization (the core feature)

    func testMapsManyVariantsToCanonical() {
        let matcher = FuzzyTermMatcher(canonicalTerms: ["Supabase"])
        for variant in ["suprabase", "superbase", "supabayse", "supabase", "Supabse"] {
            XCTAssertEqual(
                matcher.canonical(for: variant), "Supabase",
                "Expected \(variant) to map to Supabase"
            )
        }
    }

    func testDoesNotRewriteCorrectTerm() {
        let matcher = FuzzyTermMatcher(canonicalTerms: ["Supabase"])
        // Exact case match => nothing to fix => nil.
        XCTAssertNil(matcher.canonical(for: "Supabase"))
        // Folded match but wrong case => return canonical (casing fix).
        XCTAssertEqual(matcher.canonical(for: "supabase"), "Supabase")
    }

    func testDoesNotRewriteUnrelatedWords() {
        let matcher = FuzzyTermMatcher(canonicalTerms: ["Supabase"])
        // Different first letter — strong guard against false positives.
        XCTAssertNil(matcher.canonical(for: "database"))
        XCTAssertNil(matcher.canonical(for: "the"))
        XCTAssertNil(matcher.canonical(for: "amazing"))
    }

    func testShortTokensRequireExactMatchOnly() {
        let matcher = FuzzyTermMatcher(canonicalTerms: ["AWS"], minLength: 5)
        // Too short to fuzzy-match; "ays" should not become AWS.
        XCTAssertNil(matcher.canonical(for: "ays"))
    }

    func testAmbiguousMatchIsRejected() {
        // Two equally-close canonical terms => refuse to guess.
        let matcher = FuzzyTermMatcher(canonicalTerms: ["Kafka", "Kavka"])
        XCTAssertNil(matcher.canonical(for: "Karka"))
    }

    // MARK: - Whole-text application

    func testApplyPreservesPunctuationAndSpacing() {
        let matcher = FuzzyTermMatcher(canonicalTerms: ["Supabase"])
        let input = "I deployed to suprabase, then to superbase!"
        let output = matcher.apply(to: input)
        XCTAssertEqual(output, "I deployed to Supabase, then to Supabase!")
    }

    func testApplyLeavesTextUnchangedWhenNoTerms() {
        let matcher = FuzzyTermMatcher(canonicalTerms: [])
        XCTAssertTrue(matcher.isEmpty)
        let input = "nothing to change here"
        XCTAssertEqual(matcher.apply(to: input), input)
    }

    func testApplyHandlesEmptyText() {
        let matcher = FuzzyTermMatcher(canonicalTerms: ["Supabase"])
        XCTAssertEqual(matcher.apply(to: ""), "")
    }
}
