import XCTest
@testable import CodeIsland

final class SessionTokenUsageStoreTests: XCTestCase {
    func testClaudeSessionTotalsAllTokenClasses() {
        let jsonl = """
        {"message":{"usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":30,"cache_creation_input_tokens":40}}}
        {"message":{"usage":{"input_tokens":1,"output_tokens":2,"cache_read_input_tokens":3,"cache_creation_input_tokens":4}}}
        """

        XCTAssertEqual(SessionTokenUsageStore.claudeTokenTotal(from: Data(jsonl.utf8)), 110)
    }

    func testCodexSessionUsesLatestCumulativeMaximum() {
        let jsonl = """
        {"payload":{"info":{"total_token_usage":{"total_tokens":100}}}}
        {"payload":{"info":{"total_token_usage":{"total_tokens":260}}}}
        {"payload":{"info":{"total_token_usage":{"total_tokens":220}}}}
        """

        XCTAssertEqual(SessionTokenUsageStore.codexTokenTotal(from: Data(jsonl.utf8)), 260)
    }
}
