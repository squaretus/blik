import XCTest
@testable import BlikCore

final class UpdateInfoTests: XCTestCase {

    // MARK: - SemanticVersion parsing (valid)

    func testParseValidVersionSimple() {
        let v = SemanticVersion(string: "1.0.0")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 1)
        XCTAssertEqual(v?.minor, 0)
        XCTAssertEqual(v?.patch, 0)
    }

    func testParseValidVersionMultiDigit() {
        let v = SemanticVersion(string: "2.10.3")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 2)
        XCTAssertEqual(v?.minor, 10)
        XCTAssertEqual(v?.patch, 3)
    }

    func testParseValidVersionLeadingZero() {
        let v = SemanticVersion(string: "0.1.0")
        XCTAssertNotNil(v)
        XCTAssertEqual(v?.major, 0)
        XCTAssertEqual(v?.minor, 1)
        XCTAssertEqual(v?.patch, 0)
    }

    // MARK: - SemanticVersion parsing (invalid)

    func testParseInvalidAlphabetic() {
        XCTAssertNil(SemanticVersion(string: "abc"))
    }

    func testParseInvalidTwoParts() {
        XCTAssertNil(SemanticVersion(string: "1.0"))
    }

    func testParseInvalidEmpty() {
        XCTAssertNil(SemanticVersion(string: ""))
    }

    func testParseInvalidFourParts() {
        XCTAssertNil(SemanticVersion(string: "1.0.0.0"))
    }

    func testParseInvalidNonNumeric() {
        XCTAssertNil(SemanticVersion(string: "1.x.0"))
    }

    // MARK: - SemanticVersion comparison

    func testComparisonPatchDiffers() {
        let a = SemanticVersion(string: "1.0.0")!
        let b = SemanticVersion(string: "1.0.1")!
        XCTAssertTrue(a < b)
        XCTAssertFalse(b < a)
    }

    func testComparisonMinorDiffers() {
        let a = SemanticVersion(string: "1.0.0")!
        let b = SemanticVersion(string: "1.1.0")!
        XCTAssertTrue(a < b)
    }

    func testComparisonMajorDiffers() {
        let a = SemanticVersion(string: "1.0.0")!
        let b = SemanticVersion(string: "2.0.0")!
        XCTAssertTrue(a < b)
    }

    func testComparisonNumericNotLexicographic() {
        // 1.9.0 < 1.10.0 — числовая сортировка, не строковая
        let a = SemanticVersion(string: "1.9.0")!
        let b = SemanticVersion(string: "1.10.0")!
        XCTAssertTrue(a < b)
    }

    // MARK: - SemanticVersion equality

    func testEquality() {
        let a = SemanticVersion(string: "1.0.0")!
        let b = SemanticVersion(string: "1.0.0")!
        XCTAssertEqual(a, b)
    }

    func testInequality() {
        let a = SemanticVersion(string: "1.0.0")!
        let b = SemanticVersion(string: "1.0.1")!
        XCTAssertNotEqual(a, b)
    }

    func testEqualVersionsNotLessThan() {
        let a = SemanticVersion(string: "2.3.4")!
        let b = SemanticVersion(string: "2.3.4")!
        XCTAssertFalse(a < b)
    }

    // MARK: - SemanticVersion description

    func testDescription() {
        let v = SemanticVersion(major: 3, minor: 2, patch: 1)
        XCTAssertEqual(v.description, "3.2.1")
    }

    // MARK: - SemanticVersion memberwise init

    func testMemberwiseInit() {
        let v = SemanticVersion(major: 5, minor: 12, patch: 0)
        XCTAssertEqual(v.major, 5)
        XCTAssertEqual(v.minor, 12)
        XCTAssertEqual(v.patch, 0)
    }

    // MARK: - UpdateInfo Codable

    func testUpdateInfoCodableRoundTrip() throws {
        let info = UpdateInfo(
            currentVersion: "1.0.0",
            latestVersion: "1.2.0",
            downloadURL: "https://example.com/Blik-1.2.0.pkg",
            releaseNotes: "Bug fixes and improvements",
            isNewer: true
        )

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(UpdateInfo.self, from: data)
        XCTAssertEqual(decoded, info)
    }

    func testUpdateInfoCodableWithNilReleaseNotes() throws {
        let info = UpdateInfo(
            currentVersion: "1.0.0",
            latestVersion: "1.0.0",
            downloadURL: "https://example.com/pkg",
            releaseNotes: nil,
            isNewer: false
        )

        let data = try JSONEncoder().encode(info)
        let decoded = try JSONDecoder().decode(UpdateInfo.self, from: data)
        XCTAssertEqual(decoded, info)
        XCTAssertNil(decoded.releaseNotes)
    }

    // MARK: - UpdateInfo Equatable

    func testUpdateInfoEquality() {
        let a = UpdateInfo(currentVersion: "1.0.0", latestVersion: "1.1.0",
                           downloadURL: "https://a.com/pkg", releaseNotes: "notes", isNewer: true)
        let b = UpdateInfo(currentVersion: "1.0.0", latestVersion: "1.1.0",
                           downloadURL: "https://a.com/pkg", releaseNotes: "notes", isNewer: true)
        XCTAssertEqual(a, b)
    }

    func testUpdateInfoInequality() {
        let a = UpdateInfo(currentVersion: "1.0.0", latestVersion: "1.1.0",
                           downloadURL: "https://a.com/pkg", releaseNotes: nil, isNewer: true)
        let b = UpdateInfo(currentVersion: "1.0.0", latestVersion: "1.2.0",
                           downloadURL: "https://a.com/pkg", releaseNotes: nil, isNewer: true)
        XCTAssertNotEqual(a, b)
    }
}
