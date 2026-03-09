import XCTest
@testable import Yap

final class TypistTests: XCTestCase {

    @MainActor
    func testPasteSetsStringOnPasteboard() {
        let pasteboard = NSPasteboard.general
        Typist.paste("Hello world")

        let expectation = XCTestExpectation(description: "Pasteboard has text after paste")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertEqual(pasteboard.string(forType: .string), "Hello world")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testPasteWithTrailingSpace() {
        let pasteboard = NSPasteboard.general
        Typist.paste("Hello", appendTrailingSpace: true)

        let expectation = XCTestExpectation(description: "Pasteboard has text with trailing space")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            XCTAssertEqual(pasteboard.string(forType: .string), "Hello ")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testPasteEmptyStringDoesNothing() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)

        Typist.paste("")

        XCTAssertEqual(pasteboard.string(forType: .string), "original")
    }
}
