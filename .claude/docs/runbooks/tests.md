# Tests

Run, filter, and extend the XCTest suite (four test targets, ~89 tests).

## Steps

1. **Run all tests** (debug build, all three targets):
   ```bash
   swift test
   ```

2. **Run a single target**:
   ```bash
   swift test --filter BlikCoreTests
   swift test --filter BlikXPCTests
   swift test --filter BlikSharedTests
   swift test --filter blikTests
   ```

3. **Run a single class or method** (pattern is `Target.Class/method`):
   ```bash
   swift test --filter BlikCoreTests.SMCTypesTests
   swift test --filter BlikCoreTests.SMCTypesTests/testFpe2RoundTrip
   swift test --filter UpdateServiceTests           # short pattern (class name)
   swift test --filter testStripANSI                # short pattern (method)
   ```

4. **Release-mode test run** (rarely needed; default debug is correct for diagnosing):
   ```bash
   swift test -c release
   ```

## What is covered

- `Tests/BlikCoreTests/SMCTypesTests.swift` — `SMCFormat` conversions: `FourCharCode` round-trip, `FPE2` (fan RPM, big-endian), `SP78` (temperature, incl. negative), `FLT` (little-endian on Apple Silicon, round-trip); `SensorGroup` ordering and titles.
- `Tests/BlikCoreTests/AppStateTests.swift` — `AppState` defaults / custom init, `Constants.speedPresets` shape (`[0,25,50,75,100]`), preset → RPM math (`min + (max-min) * pct / 100`).
- `Tests/BlikCoreTests/UpdateInfoTests.swift` — `SemanticVersion` parsing (valid + invalid forms, `1.9.0 < 1.10.0` numeric not lex), comparison, equality, description, memberwise init; `UpdateInfo` Codable round-trip and Equatable.
- `Tests/BlikCoreTests/UpdateCheckerParsingTests.swift` — GitHub Releases JSON parsing (mirrors `BlikHelper.UpdateChecker.parseRelease`, which is not importable here): `tag_name` with/without `v` prefix, finding `.pkg` asset (first wins on multiple), null `body`, empty assets, invalid JSON.
- `Tests/BlikXPCTests/UpdateServiceTests.swift` — `UpdateService.check` / `checkForced` / `install` with a `MockBlikHelper` (full `BlikHelperProtocol` stub). Covers `.available` / `.upToDate` / `.error` paths, invalid data, nil-without-error, and that `checkForced` uses a separate handler from `check`.
- `Tests/BlikSharedTests/TelemetrySenderTests.swift` — `TelemetrySender.runLoop` against an actor-based `MockHTTPSender`: backlog drain in one tick, per-batch backoff on 500, failing batch not blocking other ready batches, sender-wide 429 throttle gate (with and without `Retry-After` header), no-op on empty buffer.
- `Tests/BlikSharedTests/OAuthClientTests.swift` — `OAuthClient` local invariants: `constantTimeEquals` (equal/different/length-mismatch/empty), `handleCallback` error paths (missing state in URL, no stored state, wrong state, expired flow >10 min, missing code), and that Keychain flow data (`oauthState`/`oauthVerifier`/`oauthFlowStartedAt`) is always cleared on error.
- `Tests/blikTests/DashboardViewTests.swift` — `DashboardView.stripANSI` removes color/cursor escape sequences.
- `Tests/blikTests/KeyboardInputTests.swift` — `KeyEvent` cases (`.preset(0/25/50/75/100)`, `.quit`, `.up/.down/.pageUp/.pageDown/.none`). Removed cases (`.left/.right/.tab/.autoMode`) are verified at compile time.

## Adding new tests

- File layout: drop a new `*.swift` file into the matching target directory under `Tests/` — SPM picks it up automatically, no `Package.swift` edit required.
- Style (consistent across existing files):
  - `import XCTest` + `@testable import <Target>`.
  - `final class <Name>Tests: XCTestCase { ... }`.
  - Methods named `func testXxx()`, grouped by `// MARK: -` sections.
  - Asserts: `XCTAssertEqual`, `XCTAssertNil/NotNil`, `XCTAssertTrue/False`, `XCTAssertThrowsError`, `accuracy:` for floats.
  - Async/XPC-style callbacks: use `let exp = expectation(description: ...)` + `waitForExpectations(timeout: 1.0)` (see `UpdateServiceTests`).
- Pick the right target:
  - Pure `BlikCore` logic (formats, models, constants) → `BlikCoreTests`.
  - `BlikXPC` service layer or anything mocking `BlikHelperProtocol` → `BlikXPCTests` (copy `MockBlikHelper` pattern; it implements every method as a no-op so partial stubs don't break compilation).
  - `BlikShared` non-UI logic (telemetry, OAuth, VM helpers) → `BlikSharedTests`.
  - CLI internals (UI, keys, ANSI) → `blikTests`.
- Test names mix Russian comments and English identifiers — match the surrounding file.

## Common issues

- **`UpdateChecker` cannot be imported from tests.** It lives in the `BlikHelper` executable target, not a library. `UpdateCheckerParsingTests` reproduces the GitHub-JSON `Decodable` structs locally and tests parsing logic in isolation — extend the local copies if `UpdateChecker.parseRelease` changes shape.
- **SMC/IOKit not exercised.** Tests cover format conversions and models only; there is no integration test that talks to the real SMC. Don't add tests that touch `SMCConnection` — they require IOKit and root privileges and won't run on CI / `swift test`.
- **SwiftUI views (`BlikApp`, `BlikMenuBar`) are not under test.** No test target depends on them. `BlikShared` is partially covered by `BlikSharedTests` (non-UI service classes only).
- **`@testable` is required** for `blikTests` (accesses internal `DashboardView.stripANSI`, `KeyEvent`) and for the `BlikCore`/`BlikXPC` targets.
- **`MockBlikHelper` must stay in sync with `BlikHelperProtocol`.** When the XPC protocol gains a method, `UpdateServiceTests` will fail to compile until the mock implements it (currently all unused methods return `"Not implemented"` / `nil`).

## Where logs / metrics

- Output goes to stdout; failed assertions print file:line. No separate test log file.
- Xcode integration: `open Package.swift` → run via Cmd+U for per-test navigation.
