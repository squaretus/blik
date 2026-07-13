import XCTest
@testable import blik

final class DashboardViewTests: XCTestCase {
    func testStripANSI() {
        XCTAssertEqual(DashboardView.stripANSI("\u{1B}[31mhello\u{1B}[0m"), "hello")
        XCTAssertEqual(DashboardView.stripANSI("\u{1B}[?25l"), "")
        XCTAssertEqual(DashboardView.stripANSI("plain text"), "plain text")
        XCTAssertEqual(DashboardView.stripANSI("\u{1B}[1m\u{1B}[36m test \u{1B}[0m"), " test ")
    }
}
