# Telemetry backlog never drains after network outage

## Symptoms
- `TelemetrySender.bufferedCount()` keeps growing (or stays flat) after a network outage ends.
- `lastSuccessTimestamp` resumes ticking (one batch per `tickInterval`), so it looks healthy — but `bufferedBytes` does not shrink back to ~0.
- Symptom is invisible in steady state: shows up only after an outage / sleep / 5xx burst, once `buffer.nextReady()` has accumulated multiple ready batches.

## Scope
- `Sources/BlikShared/Telemetry/TelemetrySender.swift` — `runLoop`, `drainReady`, `tryFlushOne`.
- Interaction with `TelemetryBuffer` (`nextReady`, `ackSuccess`, `ackFailure`).
- Capture cadence (whoever calls `enqueue(_:)`) is the other half of the rate equation.

## Root cause
`runLoop` used to flush exactly **one** batch per tick: `await tryFlushOne()` then sleep `tickInterval`. With `tickInterval == settings.intervalSeconds`, capture produces ~1 batch per tick under normal load, so drain rate equals enqueue rate. After an outage builds up N pending batches, the steady-state 1:1 ratio means the backlog **never** shrinks — it just travels forward in time at the same rate as new captures.

## Reproduction
1. Start `TelemetrySender.runLoop(tickInterval: 30)` with capture producing one batch every ~30s.
2. Block network (or force `apiClient.postRaw` to return `.http(503, _)`) for ~10 minutes → backlog grows to ~20 batches.
3. Restore network.
4. Observe `bufferedCount` — it stays ~20 indefinitely (drains one, gains one each tick).

## Fix
Split `runLoop` into tick scheduler + drain pass:

- `runLoop` sleeps `tickInterval`, then calls `drainReady()`.
- `drainReady()` is a private inner loop: while `buffer.nextReady() != nil` → `tryFlushOne()`. On `lastError != nil` → `return` (wait for next tick so `nextAttemptAt` backoff can expire). Between successful batches — 100ms `Task.sleep` (lets backend breathe + gives `Task.cancellation` a chance during shutdown).
- Steady-state behaviour unchanged (one ready batch per tick → one flush per tick). Recovery is the only path that changes: a single tick now drains the entire backlog (modulo the 100ms inter-batch throttle and any per-batch failure that breaks the loop).

## Regression checks
- [ ] After simulated outage, `bufferedCount` drops to 0 within one tick + N*100ms once network is restored.
- [ ] Steady state (capture rate <= 1 batch/tick) shows exactly one flush per tick, not a burst.
- [ ] A failure mid-drain (e.g. 5xx on batch #3) leaves the remaining batches in the buffer and stops the drain — next tick resumes after backoff.
- [ ] `Task.cancel()` during a drain returns within ~100ms (sleep is the only suspension point inside `drainReady`).
- [ ] 429 with retry-after still routes through `ackFailure(_, retryAfter:)`; drain returns immediately on `lastError != nil`.

## Related files
- `Sources/BlikShared/Telemetry/TelemetrySender.swift`
- `Sources/BlikShared/Telemetry/TelemetryBuffer.swift`

## Invariant (added by this fix)
- One tick = drain until empty OR until a failure. Not one tick = one batch.
- Between successful batches inside a single drain: 100ms throttle.
- A failure inside a drain ends the drain immediately; backoff is honoured by the next tick (not by inner-loop sleep).
