import XCTest
@testable import Yap

final class ActivityLogTests: XCTestCase {

    @MainActor
    func testAppendRecord() {
        let log = ActivityLog()
        log.clear()

        let record = ActivityRecord(text: "Hello", engine: .dictation, wasEnhanced: false)
        log.append(record)

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records.first?.text, "Hello")
        XCTAssertEqual(log.records.first?.engine, "dictation")
        XCTAssertFalse(log.records.first?.wasEnhanced ?? true)
    }

    @MainActor
    func testAppendIgnoresEmpty() {
        let log = ActivityLog()
        log.clear()

        log.append(ActivityRecord(text: "", engine: .dictation, wasEnhanced: false))
        XCTAssertTrue(log.records.isEmpty)
    }

    @MainActor
    func testRecordsInsertedAtFront() {
        let log = ActivityLog()
        log.clear()

        log.append(ActivityRecord(text: "First", engine: .dictation, wasEnhanced: false))
        log.append(ActivityRecord(text: "Second", engine: .whisper, wasEnhanced: false))

        XCTAssertEqual(log.records.count, 2)
        XCTAssertEqual(log.records[0].text, "Second")
        XCTAssertEqual(log.records[1].text, "First")
    }

    @MainActor
    func testMaxRecordsLimit() {
        let log = ActivityLog()
        log.clear()

        for i in 0..<55 {
            log.append(ActivityRecord(text: "Item \(i)", engine: .dictation, wasEnhanced: false))
        }

        XCTAssertEqual(log.records.count, 50)
        XCTAssertEqual(log.records.first?.text, "Item 54")
    }

    @MainActor
    func testMaxRecordsKeepsNewest() {
        let log = ActivityLog()
        log.clear()

        for i in 0..<55 {
            log.append(ActivityRecord(text: "Item \(i)", engine: .dictation, wasEnhanced: false))
        }

        XCTAssertEqual(log.records.last?.text, "Item 5")
    }

    @MainActor
    func testRemoveRecord() {
        let log = ActivityLog()
        log.clear()

        log.append(ActivityRecord(text: "Keep", engine: .dictation, wasEnhanced: false))
        log.append(ActivityRecord(text: "Delete me", engine: .dictation, wasEnhanced: false))

        let idToDelete = log.records.first!.id
        log.remove(id: idToDelete)

        XCTAssertEqual(log.records.count, 1)
        XCTAssertEqual(log.records.first?.text, "Keep")
    }

    @MainActor
    func testRemoveNonExistentIdIsNoop() {
        let log = ActivityLog()
        log.clear()

        log.append(ActivityRecord(text: "A", engine: .dictation, wasEnhanced: false))
        log.remove(id: UUID())

        XCTAssertEqual(log.records.count, 1)
    }

    @MainActor
    func testClear() {
        let log = ActivityLog()
        log.append(ActivityRecord(text: "A", engine: .dictation, wasEnhanced: false))
        log.append(ActivityRecord(text: "B", engine: .whisper, wasEnhanced: true))

        log.clear()
        XCTAssertTrue(log.records.isEmpty)
    }

    func testActivityRecordCodable() throws {
        let record = ActivityRecord(text: "Test", engine: .parakeet, wasEnhanced: true)
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(ActivityRecord.self, from: data)

        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.text, "Test")
        XCTAssertEqual(decoded.engine, "parakeet")
        XCTAssertTrue(decoded.wasEnhanced)
    }

    func testActivityRecordHasUniqueIDs() {
        let a = ActivityRecord(text: "A", engine: .dictation, wasEnhanced: false)
        let b = ActivityRecord(text: "A", engine: .dictation, wasEnhanced: false)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testRelativeStringJustNow() {
        XCTAssertEqual(Date().relativeString, "Just now")
    }

    func testRelativeStringJustBeforeOneMinute() {
        XCTAssertEqual(Date(timeIntervalSinceNow: -59).relativeString, "Just now")
    }

    func testRelativeStringAtOneMinute() {
        XCTAssertEqual(Date(timeIntervalSinceNow: -60).relativeString, "1 min ago")
    }

    func testRelativeStringMinutesAgo() {
        XCTAssertEqual(Date(timeIntervalSinceNow: -180).relativeString, "3 min ago")
    }

    func testRelativeStringHoursAgo() {
        XCTAssertEqual(Date(timeIntervalSinceNow: -7200).relativeString, "2 hr ago")
    }

    func testRelativeStringYesterday() {
        XCTAssertEqual(Date(timeIntervalSinceNow: -86400).relativeString, "Yesterday")
    }

    func testRelativeStringOlderThanYesterday() {
        let twoDaysAgo = Date(timeIntervalSinceNow: -172_801)
        let result = twoDaysAgo.relativeString
        XCTAssertNotEqual(result, "Yesterday")
        XCTAssertFalse(result.isEmpty)
    }
}
