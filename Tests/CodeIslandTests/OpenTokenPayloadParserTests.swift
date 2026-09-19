import XCTest
@testable import CodeIsland

final class OpenTokenPayloadParserTests: XCTestCase {
    func testParsesSecondObjectFromConcatenatedPayload() throws {
        let payload = #"{"rows":[],"sessions":[]}{"v2_hourly":[{"hour_utc":"2026-09-19T06","tool":"codex","model":"gpt-6-astra","input":10,"output":20,"cache_read":30,"cache_write":40}],"v2_sessions":[]}"#
        let records = try OpenTokenPayloadParser.parse(Data(payload.utf8))

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].tool, "codex")
        XCTAssertEqual(records[0].model, "gpt-6-astra")
        XCTAssertEqual(records[0].totalTokens, 100)
    }

    func testSplitterHandlesBracesAndEscapesInsideStrings() {
        let payload = #"{"value":"a}b\\\"c"}{"v2_hourly":[],"v2_sessions":[]}"#
        let objects = OpenTokenPayloadParser.splitTopLevelJSONObjects(Data(payload.utf8))

        XCTAssertEqual(objects.count, 2)
    }

    func testMissingV2PayloadThrows() {
        let payload = #"{"rows":[],"sessions":[]}"#
        XCTAssertThrowsError(try OpenTokenPayloadParser.parse(Data(payload.utf8)))
    }
}
