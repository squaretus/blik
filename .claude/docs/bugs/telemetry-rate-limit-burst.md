# Telemetry sender ignores `Retry-After` and bursts through per-device rate limit

## Symptoms
- macOS app OTLP uploads return `HTTP 429` from backend in a tight burst right after a network outage / sleep ends.
- Server logs (`backend/app/services/throttle.py:otlp_ingest_limiter`) show the device hitting the per-device limit (60 req/min) within seconds.
- Client behaviour: backlog drains exactly one batch, then immediately tries the next ready batch, which also fails with 429, and so on until `nextAttemptAt` (30s) finally throttles per-batch.
- `Retry-After: 60` header from server is **ignored** by client — no sender-wide pause.
- Net effect: every ~30s the client sends a fresh burst of ~10 batches, each rejected with 429. The backlog never clears.

## Scope
- `Sources/BlikShared/Telemetry/TelemetrySender.swift` — `drainReady`, `tryFlushOne`, `sendBatch`, `SenderError`.
- Interaction with backend rate limiter `backend/app/services/throttle.py:otlp_ingest_limiter` (per-device, 60 req/min).
- Related: previous fix in `bugs/telemetry-backlog-stuck.md` introduced `drainReady` that drains entire backlog per tick — this exposed the rate-limit issue because pre-fix only one batch per tick was sent.

## Root cause
Two coupled defects:

1. **`Retry-After` was not parsed.** On 429, `sendBatch` returned a generic `SenderError.http(429)`. `tryFlushOne` translated this into `ackFailure(30)` — fixed 30s per-**batch** retry. The server's recommended back-off (`Retry-After: 60`) was discarded.

2. **Throttle scope was per-batch, not sender-wide.** `ackFailure(delay)` sets `nextAttemptAt` on the **single** batch being processed. The next call to `buffer.nextReady()` returns a **different** batch (same backend, same device, same 429-worthy state) whose `nextAttemptAt` is still in the past. `drainReady` happily sends it 100ms later → another 429. Repeat for every ready batch in the backlog.

The combination: post-outage backlog of N batches → one drain tick fires N requests in N * 100ms → backend per-device limiter rejects everything after the 60th in the minute, returns `Retry-After: 60` on each → client retries the same burst 30s later. OTLP spec is explicit: client SHOULD honour `Retry-After`, and throttling MUST be sender-wide (not per-batch) because the limit is per-sender on the server.

## Reproduction
1. Run `TelemetrySender` with capture producing one batch every ~30s and `tickInterval` ~30s.
2. Block network for ~10 minutes → backlog grows to ~20 batches.
3. Restore network.
4. Observe: client sends ~20 requests in ~2s, server returns 429 + `Retry-After: 60` on most of them, backlog drains ~1-2 batches and the rest get `ackFailure(30)` → next tick repeats the burst.
5. Backend `otlp_ingest_limiter` counter for the device shows sustained saturation; client log shows 429s every tick.

## Fix
Two coordinated changes in `Sources/BlikShared/Telemetry/TelemetrySender.swift`:

1. **Parse `Retry-After`.** New enum case `SenderError.rateLimited(retryAfter: TimeInterval?)`. `sendBatch` on `HTTP 429` reads `Retry-After` header via new helper `parseRetryAfter(_:)` (seconds-form per RFC 7231; HTTP-date form not used by this backend). Returns `.rateLimited(retryAfter: parsed)`.

2. **Sender-wide throttle gate.** New actor state `blockedUntil: Date?`. On `.rateLimited`, `tryFlushOne` sets `blockedUntil = now + (retryAfter ?? 30)` **and** still calls `ackFailure(delay)` on the batch (so its own `nextAttemptAt` is consistent). `drainReady` checks `blockedUntil > now` at the top of each iteration and bails out immediately if the gate is closed — no batch is even pulled from the buffer.

3. **Inter-batch gap raised 100ms → 1000ms.** `defaultInterBatchGapNanos`. Even without 429s, 10 req/s exceeds the 60/min budget. 1 req/s is safely below. Field is injectable via init (`interBatchGapNanos:`) so tests can pass `50_000_000` (50ms) and not wait whole seconds.

Tests in `Tests/BlikSharedTests/TelemetrySenderTests.swift`:
- Mock rewritten: `MockResponse` (status + headers), `setStatusCodes` shortcut for legacy tests.
- All existing tests now pass `interBatchGapNanos: 50_000_000`.
- New `testRateLimitedBlocksWholeSender`: 429 + `Retry-After: 2` → all 3 ready batches blocked; after gate expires, uploads resume.
- New `testRateLimitedWithoutHeaderStillBlocks`: 429 with no `Retry-After` → default 30s sender-wide block.

## Regression checks
- [ ] After 10-min outage + 20-batch backlog, drain produces at most 1 req/sec (no burst beyond `interBatchGapNanos`).
- [ ] On 429 + `Retry-After: N`, next `drainReady` iteration exits within microseconds; no further requests until `now >= blockedUntil`.
- [ ] On 429 without `Retry-After`, `blockedUntil = now + 30s`.
- [ ] Steady state (1 batch / 30s capture) — unaffected, no spurious 1s gaps because only one batch is drained per tick.
- [ ] Both `nextAttemptAt` (per-batch) and `blockedUntil` (sender-wide) are honoured — a batch failing 5xx still backs off per-batch even if `blockedUntil` is unset.
- [ ] `Task.cancel()` during the gate wait returns promptly (no sleep inside the gate-check path; gate is checked, then loop returns).

## Related files
- `Sources/BlikShared/Telemetry/TelemetrySender.swift`
- `Tests/BlikSharedTests/TelemetrySenderTests.swift`
- `backend/app/services/throttle.py` (server side — `otlp_ingest_limiter`, 60 req/min per device)

## Invariants (added by this fix)
- 429 throttling is **sender-wide**, not per-batch. `blockedUntil` gates the entire `drainReady` loop, not individual batches.
- `Retry-After` header (seconds form) is authoritative when present; absent → 30s default.
- `defaultInterBatchGapNanos = 1_000_000_000` (1s). Anything smaller risks tripping the 60/min budget under backlog drain. Test override is the only legitimate way to use a smaller value.
- Two backoff layers coexist: per-batch `nextAttemptAt` (handles 5xx + network errors), sender-wide `blockedUntil` (handles 429). Both must be checked before sending.

## Related docs
- bugs/telemetry-backlog-stuck.md — the prior `drainReady` fix that made the backlog drain in one tick; this bug is its direct follow-on.
