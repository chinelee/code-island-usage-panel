import XCTest
@testable import CodeIsland

final class UsageFetcherTests: XCTestCase {
    func testClassifiesWeeklyPrimaryWindowByDuration() {
        let rateLimit: [String: Any] = [
            "primary_window": [
                "used_percent": 67.0,
                "limit_window_seconds": 604_800,
                "reset_at": Date().addingTimeInterval(5_000).timeIntervalSince1970,
            ],
        ]

        let usage = UsageFetcher.makeCodexUsage(rateLimit: rateLimit, plan: "pro")

        XCTAssertEqual(usage.weekly.percentInt, 67)
        XCTAssertNotNil(usage.weekly.resetAt)
        XCTAssertNil(usage.fiveHour.resetAt)
    }

    func testClassifiesShortAndWeeklyWindowsIndependently() {
        let rateLimit: [String: Any] = [
            "primary_window": [
                "used_percent": 12.0,
                "limit_window_seconds": 18_000,
                "reset_at": Date().addingTimeInterval(1_000).timeIntervalSince1970,
            ],
            "secondary_window": [
                "used_percent": 44.0,
                "limit_window_seconds": 604_800,
                "reset_at": Date().addingTimeInterval(8_000).timeIntervalSince1970,
            ],
        ]

        let usage = UsageFetcher.makeCodexUsage(rateLimit: rateLimit, plan: "pro")

        XCTAssertEqual(usage.fiveHour.percentInt, 12)
        XCTAssertEqual(usage.weekly.percentInt, 44)
    }
}
