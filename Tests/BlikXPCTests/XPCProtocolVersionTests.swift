import XCTest
import BlikCore
@testable import BlikXPC

/// Инварианты версии XPC-протокола.
///
/// Регресс релиза 1.0.0/1.1.0: `build.sh` подставлял релизную версию в
/// `helperVersion`, из-за чего свежесобранный helper (1.x) не проходил
/// собственные capability-гейты (`minHelperVersionFor*` = 2.x) — приложение
/// показывало «хелпер устарел» (история недоступна) и уходило на медленный
/// legacy-поллинг без `readState`.
final class XPCProtocolVersionTests: XCTestCase {

    func testProtocolVersionIsValidSemanticVersion() {
        XCTAssertNotNil(
            SemanticVersion(string: BlikXPCConstants.protocolVersion),
            "protocolVersion должен быть валидным semver"
        )
    }

    func testFreshHelperSatisfiesReadStateGate() throws {
        let protocolVersion = try XCTUnwrap(SemanticVersion(string: BlikXPCConstants.protocolVersion))
        let minReadState = try XCTUnwrap(SemanticVersion(string: Constants.minHelperVersionForReadState))
        XCTAssertGreaterThanOrEqual(
            protocolVersion, minReadState,
            "Helper, собранный из этого дерева, обязан поддерживать readState — иначе клиент уйдёт на медленный legacy-поллинг"
        )
    }

    func testBuildScriptDoesNotSubstituteProtocolVersion() throws {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // BlikXPCTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
            .appendingPathComponent("scripts/build.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        XCTAssertFalse(
            script.contains("XPCConstants.swift"),
            "build.sh не должен подставлять релизную версию в XPCConstants — это ломает capability-гейты"
        )
    }

    func testFreshHelperSatisfiesHistoryGate() throws {
        let protocolVersion = try XCTUnwrap(SemanticVersion(string: BlikXPCConstants.protocolVersion))
        let minHistory = try XCTUnwrap(SemanticVersion(string: Constants.minHelperVersionForHistory))
        XCTAssertGreaterThanOrEqual(
            protocolVersion, minHistory,
            "Helper, собранный из этого дерева, обязан поддерживать историю — иначе графики покажут «хелпер устарел»"
        )
    }
}
