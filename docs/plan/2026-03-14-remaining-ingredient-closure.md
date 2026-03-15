# Plan: Remaining Ingredient Closure and Live Validation

Date: 2026-03-14
Parent: [`docs/adr/2026-03-13-modular-ingredient-architecture.md`](../adr/2026-03-13-modular-ingredient-architecture.md)
Status: In Progress

## Context

This plan continues from the modular ingredient architecture audit (2026-03-14). The previous Codex agent completed the sound domain implementation and stop-ingredient reversibility. This plan triages remaining work and enforces the testing mandate.

## Testing Mandate

**Critical rule**: No mocks, skips, patches, or monkey patches in live integration tests. Unit tests may use adapter-backed mocks, but live integration tests must run against actual hardware. All tests must implement proper rollback so that post-testing machine state returns to its default.

## Completed in This Cycle

### Batch 6 (AUD-022): Sound domain and `sound.set-playback-device` ingredient
- Created `src/ParsecEventExecutor/Private/Domains/sound/entry.ps1` and `lib.ps1`
- Created `src/ParsecEventExecutor/Private/Ingredients/sound-set-playback-device/` with full capture/apply/verify/reset contract
- Added `ParsecSoundAdapter` to test infrastructure for adapter-backed unit testing
- 4 new tests passing

### Batch 4 (AUD-013): Reversible stop ingredients
- Added `reset` operation to `process.stop` and `service.stop`
- `process.stop` reset: restarts the process if it was originally running, no-op if it was already stopped
- `service.stop` reset: restarts the service if it was originally running, no-op if it was already stopped
- Added `ResetStopped` method to both process and service domains
- 4 new tests covering reset and skip-reset paths

### Pre-existing bug fix: Process domain closure scoping
- Refactored process domain from `.GetNewClosure()` scriptblock pattern to `lib.ps1` function pattern
- This resolved a pre-existing `New-ParsecResult` CommandNotFoundException in the aggregate `Ingredients.Tests.ps1` context
- Aligned process domain architecture with service domain pattern

### Executor test fix
- Updated "no reset support" compensation test to use `command.invoke` (which truly lacks reset) instead of `service.stop` (which now has reset)

### Test Results
- Full suite: **113 passed, 0 failed, 0 skipped**

## Remaining Work (Priority Order)

### 1. Live restore validation (AUD-002) — HIGH
Run cooperative live restore audit for display-critical ingredients:
1. `display.set-enabled` — enable/disable monitor, verify restore
2. `display.set-primary` — switch primary, verify restore
3. `display.set-activedisplays` — change active set, verify restore
4. `display.persist-topology` — persist and restore topology
5. `display.snapshot reset` — full snapshot round-trip

**Constraints**: One ingredient at a time. Stop on residual drift. Fix defects before testing next.

### 2. Live sound validation — MEDIUM
Run `sound.set-playback-device` against real hardware:
1. Capture current default playback device
2. Switch to an alternate device
3. Verify the switch
4. Reset to original
5. Verify restoration

**Prerequisite**: `AudioDeviceCmdlets` module or MSFT_AudioDevice WMI class available.

### 3. Task scheduling pipeline validation — MEDIUM
Run a full recipe through the executor and verify:
1. Graph validation (cycle detection, dependency ordering)
2. Topological step execution
3. Rollback on failure (reverse-order compensation)
4. State persistence (executor-state.json, run history, event journal)

Use `recipes/enter-mobile.toml` and `recipes/return-desktop.toml` as live validation targets.

### 4. Promote wallpaper/background to first-class ingredient (AUD-016) — LOW
Add `personalization.set-wallpaper` ingredient with capture/apply/verify/reset.

### 5. Add process.restart and service.restart (AUD-021) — LOW
Now that stop ingredients are reversible, restart can be built on top.

### 6. Display domain decomposition (AUD-008) — LOW
Split display domain internally after live behavior is proven correct.

### 7. Documentation cleanup (AUD-010) — LOW
Update README and stale docs after all capability work is complete.

## Live Integration Test Requirements

All live integration tests must:
1. Capture baseline state before any mutation
2. Execute one mutation at a time
3. Verify the mutation through public inspection (not internal state)
4. Reset to baseline using the ingredient's reset operation
5. Verify baseline restoration through public inspection
6. Report exact pass/fail with residual drift details
7. Never leave the machine in a modified state on test exit

Adapter-backed unit tests (in `tests/*.Tests.ps1`) may use the adapter injection pattern for isolated testing without live hardware side effects.
