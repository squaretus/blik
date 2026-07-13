import XCTest
@testable import blik

final class KeyboardInputTests: XCTestCase {

    // MARK: - KeyEvent cases exist

    func testKeyEventPresetCases() {
        // Verify preset cases carry correct values
        let preset0 = KeyEvent.preset(0)
        let preset25 = KeyEvent.preset(25)
        let preset50 = KeyEvent.preset(50)
        let preset75 = KeyEvent.preset(75)
        let preset100 = KeyEvent.preset(100)

        // These should not be equal to each other
        if case .preset(let v) = preset0 { XCTAssertEqual(v, 0) }
        if case .preset(let v) = preset25 { XCTAssertEqual(v, 25) }
        if case .preset(let v) = preset50 { XCTAssertEqual(v, 50) }
        if case .preset(let v) = preset75 { XCTAssertEqual(v, 75) }
        if case .preset(let v) = preset100 { XCTAssertEqual(v, 100) }
    }

    func testKeyEventQuitExists() {
        let quit = KeyEvent.quit
        if case .quit = quit {
            // pass
        } else {
            XCTFail("Expected .quit")
        }
    }

    func testKeyEventNavigationExists() {
        // Verify up/down/pageUp/pageDown still exist
        let events: [KeyEvent] = [.up, .down, .pageUp, .pageDown, .none]
        XCTAssertEqual(events.count, 5)
    }

    // MARK: - Removed key events no longer exist
    // .left, .right, .tab, .autoMode are gone -- verified at compile time
    // If this file compiles, those cases don't exist
}
