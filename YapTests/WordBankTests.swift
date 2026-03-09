import XCTest
@testable import Yap

final class WordBankTests: XCTestCase {

    @MainActor
    func testAddWord() {
        let bank = WordBank()
        bank.removeAll()

        bank.add("SwiftUI")
        XCTAssertEqual(bank.words, ["SwiftUI"])
    }

    @MainActor
    func testAddWordTrimsWhitespace() {
        let bank = WordBank()
        bank.removeAll()

        bank.add("  hello  ")
        XCTAssertEqual(bank.words, ["hello"])
    }

    @MainActor
    func testAddWordIgnoresEmpty() {
        let bank = WordBank()
        bank.removeAll()

        bank.add("")
        bank.add("   ")
        XCTAssertTrue(bank.words.isEmpty)
    }

    @MainActor
    func testAddWordIgnoresDuplicate() {
        let bank = WordBank()
        bank.removeAll()

        bank.add("Test")
        bank.add("test")
        bank.add("TEST")
        XCTAssertEqual(bank.words.count, 1)
    }

    @MainActor
    func testAddWordPreservesOriginalCase() {
        let bank = WordBank()
        bank.removeAll()

        bank.add("SwiftUI")
        XCTAssertEqual(bank.words.first, "SwiftUI")
    }

    @MainActor
    func testAddMultipleWords() {
        let bank = WordBank()
        bank.removeAll()

        bank.add("Alpha")
        bank.add("Beta")
        bank.add("Gamma")

        XCTAssertEqual(bank.words.count, 3)
        XCTAssertEqual(bank.words, ["Alpha", "Beta", "Gamma"])
    }

    @MainActor
    func testRemoveAtIndex() {
        let bank = WordBank()
        bank.removeAll()

        bank.add("A")
        bank.add("B")
        bank.add("C")

        bank.remove(at: IndexSet([1]))
        XCTAssertEqual(bank.words, ["A", "C"])
    }

    @MainActor
    func testRemoveFirstByIndex() {
        let bank = WordBank()
        bank.removeAll()

        bank.add("A")
        bank.add("B")

        bank.remove(at: IndexSet([0]))
        XCTAssertEqual(bank.words, ["B"])
    }

    @MainActor
    func testRemoveAtInvalidIndex() {
        let bank = WordBank()
        bank.removeAll()

        bank.add("Only")
        bank.remove(at: IndexSet([5]))
        XCTAssertEqual(bank.words.count, 1)
    }

    @MainActor
    func testRemoveByValue() {
        let bank = WordBank()
        bank.removeAll()

        bank.add("Hello")
        bank.add("World")

        bank.remove("Hello")
        XCTAssertEqual(bank.words, ["World"])
    }

    @MainActor
    func testRemoveByValueCaseInsensitive() {
        let bank = WordBank()
        bank.removeAll()

        bank.add("Hello")
        bank.remove("hello")
        XCTAssertTrue(bank.words.isEmpty)
    }

    @MainActor
    func testRemoveByValueNonExistent() {
        let bank = WordBank()
        bank.removeAll()

        bank.add("Hello")
        bank.remove("World")
        XCTAssertEqual(bank.words.count, 1)
    }

    @MainActor
    func testRemoveAll() {
        let bank = WordBank()
        bank.add("A")
        bank.add("B")
        bank.add("C")

        bank.removeAll()
        XCTAssertTrue(bank.words.isEmpty)
    }

    @MainActor
    func testAsPromptString() {
        let bank = WordBank()
        bank.removeAll()

        bank.add("Alpha")
        bank.add("Beta")
        bank.add("Gamma")

        XCTAssertEqual(bank.asPromptString, "Alpha, Beta, Gamma")
    }

    @MainActor
    func testAsPromptStringSingleWord() {
        let bank = WordBank()
        bank.removeAll()

        bank.add("Solo")
        XCTAssertEqual(bank.asPromptString, "Solo")
    }

    @MainActor
    func testAsPromptStringEmpty() {
        let bank = WordBank()
        bank.removeAll()

        XCTAssertEqual(bank.asPromptString, "")
    }
}
