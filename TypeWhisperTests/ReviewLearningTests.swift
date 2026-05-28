import XCTest
@testable import TypeWhisper

final class ReviewLearningTests: XCTestCase {

    func testLearnsNewProperNoun() {
        let original = "I deployed to superbase today"
        let edited = "I deployed to Supabase today"
        XCTAssertEqual(ReviewLearning.newTerms(original: original, edited: edited), ["Supabase"])
    }

    func testNoNewTermsWhenUnchanged() {
        let text = "nothing changed at all here"
        XCTAssertTrue(ReviewLearning.newTerms(original: text, edited: text).isEmpty)
    }

    func testIgnoresLowercaseSubstitutions() {
        let original = "go to the page"
        let edited = "go to the site"
        // Lowercase substitution => not a proper-noun signal => not learned.
        XCTAssertTrue(ReviewLearning.newTerms(original: original, edited: edited).isEmpty)
    }

    func testIgnoresPureNumbers() {
        let original = "the meeting is at noon"
        let edited = "the meeting is at 1230"
        XCTAssertTrue(ReviewLearning.newTerms(original: original, edited: edited).isEmpty)
    }

    func testPreservesCapitalization() {
        let original = "using kubernetes here"
        let edited = "using Kubernetes here"
        // Differs only in case -> same lowercased token -> not "new".
        XCTAssertTrue(ReviewLearning.newTerms(original: original, edited: edited).isEmpty)
    }

    func testDeduplicatesRepeatedNewTerm() {
        let original = "ship it"
        let edited = "ship Supabase and Supabase again"
        XCTAssertEqual(ReviewLearning.newTerms(original: original, edited: edited), ["Supabase"])
    }

    func testTokenizeHandlesPunctuation() {
        XCTAssertEqual(ReviewLearning.tokenize("Hello, world! it's fine."),
                       ["Hello", "world", "it's", "fine"])
    }
}
