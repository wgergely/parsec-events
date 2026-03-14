# Modular Ingredient Architecture Audit

Topic: Modular ingredient architecture audit after the core/domain/ingredient rewrite

Audit Surface: `src/ParsecEventExecutor`, `tests`, `recipes`, `docs/adr/2026-03-13-modular-ingredient-architecture.md`, `docs/plan/2026-03-13-modular-ingredient-architecture.md`, `docs/research/06-modular-ingredient-architecture/research.md`

Rewrite Scope: Identify remaining regressions, misses, skips, stubs, and legacy behaviors after the modular rewrite; persist current development state, testing status, live-validation status, and an assessment of event chaining.

## Summary

The monolithic runtime has been retired from the live path, and the modular `Core + Domains + Ingredients` architecture is active. The current runtime is functional enough to load ingredients lazily, execute standalone ingredients, and execute recipes through the new executor.

The migration moved materially forward in this cycle. The following architecture gaps were closed in code:

- ingredient manifests now declare domain ownership explicitly and the loader validates the declaration
- recipe execution now performs graph validation and deterministic topological scheduling before running steps
- explicit-compensation flows now support chain-wide reverse rollback of earlier successful steps
- the retired core observed-state bridge is no longer used by active domain/runtime paths
- `window.cycle-activation` is now a thin domain consumer instead of a duplicate implementation surface
- modular domain entry wiring for snapshot, personalization, display scaling, and service dispatch was repaired
- executor-state and snapshot/profile harnesses were updated to inject module-backed adapters that match the current domain contracts
- readiness now guarantees a small minimum probe budget, which removed slow-first-probe flakiness from NVIDIA wait verification

The rewrite is still not complete from a live-operability perspective. The main remaining gaps are:

- live restore fidelity for real display topology changes is still not trustworthy
- some required ingredients still do not satisfy the full reversible `capture/apply/wait/verify/reset` contract
- display remains the main complexity hotspot and still needs internal decomposition
- scale/text-scale audit visibility still needs a stronger live inspection surface
- one standalone process-token reset assertion is still red and needs either runtime confirmation or test-contract cleanup

## Current Development State

### Architecture state

- Active architecture parent: [`docs/adr/2026-03-13-modular-ingredient-architecture.md`](../adr/2026-03-13-modular-ingredient-architecture.md)
- Active implementation parent: [`docs/plan/2026-03-13-modular-ingredient-architecture.md`](../plan/2026-03-13-modular-ingredient-architecture.md)
- Retired from the live runtime path:
  - `src/ParsecEventExecutor/Private/IngredientRuntime.ps1`
  - `src/ParsecEventExecutor/Private/Core/Compat.ps1`
  - legacy ingredient `lib.ps1` package loading
- Active domain surface:
  - `command`
  - `display`
  - `nvidia`
  - `personalization`
  - `process`
  - `service`
  - `snapshot`
  - `window`
- Active concrete ingredient surface:
  - `command.invoke`
  - `display.ensure-resolution`
  - `display.persist-topology`
  - `display.set-activedisplays`
  - `display.set-enabled`
  - `display.set-orientation`
  - `display.set-primary`
  - `display.set-resolution`
  - `display.set-scaling`
  - `display.set-textscale`
  - `display.set-uiscale`
  - `display.snapshot`
  - `nvidia.add-custom-resolution`
  - `process.start`
  - `process.stop`
  - `service.start`
  - `service.stop`
  - `system.set-theme`
  - `window.cycle-activation`

### Observed live desktop state after the latest full standalone run

Observed via direct `Get-ParsecDisplay` on 2026-03-14:

| screen_id | device_name | friendly_name | enabled | is_primary | orientation | width | height |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 2 | `\\.\DISPLAY1` | `BenQ EW2775ZH` | `true` | `false` | `Landscape` | `1920` | `1080` |
| 1 | `\\.\DISPLAY2` | `PA278CV` | `true` | `true` | `Landscape` | `2560` | `1440` |
| 3 | `\\.\DISPLAY3` | `QBQ90` | `false` | `false` | `Landscape` |  |  |
| 3 | `\\.\DISPLAY4` | `QBQ90` | `false` | `false` | `Landscape` |  |  |

This observed state still does not match the user-reported expected desktop baseline because monitor 3 should have returned enabled. That is an open restore-fidelity regression.

## Testing Status

### Fresh test results

| Surface | Result | Date | Notes |
| --- | --- | --- | --- |
| `tests/StandaloneIngredient.Tests.ps1` | `33 passed, 1 failed, 0 skipped` | 2026-03-14 | Remaining failure is the token-backed `process.start` reset assertion; the runtime returns `Succeeded`, but the test still expects proof that the persisted `process_id` is consumed through a specific lookup path |
| `tests/Profile.Tests.ps1` | `3 passed, 0 failed, 0 skipped` | 2026-03-14 | Snapshot/profile flows are green after adapter injection was moved onto the module-backed path |
| `tests/ExecutorState.Tests.ps1` | `6 passed, 0 failed, 0 skipped` | 2026-03-14 | Executor-backed mobile/desktop state transitions are green again after fixing harness domain contracts and display scaling dispatch |
| `tests/NvidiaStandaloneIngredient.Tests.ps1` | `4 passed, 0 failed, 0 skipped` | 2026-03-14 | NVIDIA readiness no longer collapses to a single slow probe |
| `tests/Executor.Tests.ps1` | `15 passed, 0 failed, 0 skipped` | 2026-03-14 | Recipe-backed graph validation, ordering, rollback, and readiness behavior are green in the targeted executor suite |

### Test-surface observations

- No active `skip`, `xfail`, or pending test markers were found in `tests`.
- The current tests are not stubbed out of existence; the executor and standalone ingredient surfaces are both exercised.
- The targeted migration suites are now mostly green. The remaining red test is isolated to the token-backed `process.start` reset assertion.
- The green test state does not yet prove that all live display restore paths are correct on real hardware.
- This cycle did not rerun the broader `tests/Ingredients.Tests.ps1` aggregate suite, so any conclusions about the entire ingredient surface should still be treated as bounded to the targeted suites above.

## Live Validation Status

### Demonstrably live-tested and observed to work

- `display.set-resolution`
- `display.set-orientation`
- `display.snapshot`
- `Get-ParsecDisplay`

### Live-executed through the modular runtime, but not proven successful

- `command.invoke`
- `window.cycle-activation`

These both execute through the modular runtime and return shaped failures instead of loader/runtime crashes, which confirms the architecture path is active, but not that the ingredient behavior succeeds on the live machine.

### Test-validated but not yet proven safe on the live machine

- `display.ensure-resolution`
- `display.persist-topology`
- `display.set-activedisplays`
- `display.set-enabled`
- `display.set-primary`
- `display.set-scaling`
- `display.set-textscale`
- `display.set-uiscale`
- `nvidia.add-custom-resolution`
- `process.start`
- `process.stop`
- `service.start`
- `service.stop`
- `system.set-theme`

### Live validation gap

The current audit can prove live success for resolution and orientation changes, but it cannot yet prove that restore-token and snapshot-driven reset behavior is reliable after real topology changes. That gap is materially important because the user already observed one live restore regression.

## Event Chaining Assessment

Event chaining is implemented. It is not a stub.

Primary runtime evidence:

- `src/ParsecEventExecutor/Private/Execution.ps1`
- `tests/Executor.Tests.ps1`
- `tests/RecipeParsing.Tests.ps1`
- `recipes/enter-mobile.toml`
- `recipes/return-desktop.toml`

What is implemented in code:

- graph validation before execution
- deterministic topological ordering
- `depends_on` gating
- `mode_is` conditional execution
- retries
- readiness checks
- verification
- active snapshot propagation
- executor/run persistence
- reverse-order rollback of earlier successful explicit-compensation steps

What is currently regressed:

- the executor-backed recipe path is failing its current test surface during execution-plan construction
- the presence of graph scheduling and rollback code does not currently translate into a passing executor rollout

Assessment:

- The event-chaining mechanism is architecturally deeper than the previous audit recorded.
- The current problem is no longer "missing graph logic"; it is that the executor rollout is presently broken by a runtime type mismatch and therefore cannot be treated as working.

## Findings

### AUD-001 Resolved: Ingredient manifests now declare and enforce their domain explicitly

Every active ingredient manifest now carries `domain = ...`, and loader/catalog registration fails when the field is missing or does not match the public ingredient naming contract.

Evidence:

- active ingredient manifests under `src/ParsecEventExecutor/Private/Ingredients/*/schema.toml`
- `src/ParsecEventExecutor/Private/Core/Definitions.ps1`
- `src/ParsecEventExecutor/Private/Core/Loader.ps1`

Impact:

- manifest ownership is now explicit and enforceable
- loader behavior no longer needs active fallback inference during registration

### AUD-002 High: Live restore fidelity remains unproven and a real regression has already been observed

The latest live audit state still shows monitor 3 disabled after test execution, while the user-reported expected desktop baseline requires it to be enabled.

Evidence:

- direct live `Get-ParsecDisplay` observation on 2026-03-14
- user-reported restore regression: monitor 3 did not come back

Impact:

- snapshot and token-based reset cannot yet be treated as trustworthy on real hardware
- topology-changing ingredients remain high risk until live restore validation is completed

### AUD-003 Resolved: Recipe compensation now supports chain-wide reverse rollback

The executor now validates the step graph first, executes in deterministic topological order, and performs reverse-order rollback of earlier successful explicit-compensation steps when a later step fails and cannot self-compensate cleanly.

Evidence:

- `src/ParsecEventExecutor/Private/Execution.ps1`
- `tests/Executor.Tests.ps1`

Impact:

- multi-step flows now have structural validation plus chain rollback coverage
- live restore correctness for display topology is still an open hardware-validation concern

### AUD-004 Resolved: Event chaining is now graph-validated and topologically ordered

`depends_on` is now treated as a graph contract. Duplicate ids, unknown dependencies, self-dependencies, and cycles are rejected before execution. Ready steps are scheduled in deterministic topological order using recipe order as the tie-breaker.

Evidence:

- `src/ParsecEventExecutor/Private/Execution.ps1`
- `tests/Executor.Tests.ps1`

Impact:

- dependency mistakes now fail at preflight instead of surfacing only as runtime blockage
- execution is still intentionally single-threaded in this migration

### AUD-005 Resolved: Active runtime paths no longer depend on the core observed-state bridge

Active domain/runtime callers were rewired away from `Get-ParsecObservedState`, and the helper was removed from `Core/StateHelpers.ps1`.

Evidence:

- `src/ParsecEventExecutor/Private/Core/StateHelpers.ps1`
- `src/ParsecEventExecutor/Private/Domains/nvidia/lib.ps1`
- `src/ParsecEventExecutor/Private/Domains/personalization/Personalization.Domain.ps1`
- `src/ParsecEventExecutor/Private/Domains/snapshot/Snapshot.Domain.ps1`
- `src/ParsecEventExecutor/Private/IngredientInvocation.ps1`

Impact:

- runtime-core no longer exposes this domain behavior
- remaining live restore issues are no longer attributable to this ownership leak

### AUD-006 Resolved: The window ingredient is now a thin consumer of the window domain

`window.cycle-activation` now delegates its operational behavior to the `window` domain instead of carrying an embedded copy of the domain logic.

Evidence:

- `src/ParsecEventExecutor/Private/Domains/window/entry.ps1`
- `src/ParsecEventExecutor/Private/Ingredients/window-cycle-activation/entry.ps1`

Impact:

- duplicated window behavior has been collapsed
- future window work can stay domain-first

### AUD-007 Medium: Snapshot and personalization are still underexposed as concrete ingredient surfaces

The domains exist, but the ingredient surface is still thin:

- snapshot behavior is mainly exposed via `display.snapshot` and `display.persist-topology`
- personalization is mainly exposed via `system.set-theme`

Impact:

- the modular architecture is present, but the public capability surface is not yet balanced across domains

### AUD-008 Medium: Display has become the new complexity hotspot

The old monolith is gone, but complexity has concentrated heavily in the display domain:

- `src/ParsecEventExecutor/Private/Domains/display/Platform.ps1` is `2101` lines
- `src/ParsecEventExecutor/Private/Domains/display/Domain.ps1` is `1479` lines

Impact:

- the rewrite removed the giant cross-domain runtime, but one domain is already large enough to require internal decomposition

### AUD-009 Medium: Live audit visibility for scale and text scale is incomplete

The direct `Get-ParsecDisplay` audit capture returned real topology and orientation information, but scale and text-scale values were not exposed in the returned object shape during the audit pass.

Impact:

- current live drift in DPI and text scaling cannot be confirmed from the main inspection command alone
- that reduces confidence when auditing post-test rollback

### AUD-010 Low: Public documentation still describes compatibility shims

The runtime compat file is gone, but public documentation still exposes compatibility language.

Evidence:

- `README.md`

Impact:

- the implementation has moved further than the docs surface
- this is a documentation drift issue rather than a runtime blocker

### AUD-011 Informational: No explicit stub/skip marker debt was found in the active code paths

No meaningful `TODO`, `FIXME`, `NotImplemented`, `skip`, or `xfail` markers were found in the active runtime and test surfaces during this audit.

Impact:

- the remaining problems are architectural and behavioral rather than being openly parked as explicit stubs

### AUD-012 Resolved: The executor-backed recipe path is green again in the targeted suite

The targeted executor suite now passes after the graph executor, rollback persistence, and run-status wiring were repaired.

Evidence:

- `src/ParsecEventExecutor/Private/Execution.ps1`
- `tests/Executor.Tests.ps1`
- direct `pwsh -NoProfile -Command "Invoke-Pester -Path 'tests/Executor.Tests.ps1'"` on 2026-03-14

Impact:

- recipe-backed graph validation, ordering, rollback, and readiness behavior are working in the dedicated executor surface
- live restore correctness and full-suite coverage are still separate concerns

### AUD-013 High: Stop ingredients are not fully reversible and therefore do not satisfy the required core ingredient contract

`process.stop` and `service.stop` expose `capture`, `apply`, and `verify`, but they do not expose `reset`. That means stop-oriented management ingredients cannot restore prior state after a stop action.

Evidence:

- `src/ParsecEventExecutor/Private/Ingredients/process-stop/schema.toml`
- `src/ParsecEventExecutor/Private/Ingredients/process-stop/entry.ps1`
- `src/ParsecEventExecutor/Private/Ingredients/service-stop/schema.toml`
- `src/ParsecEventExecutor/Private/Ingredients/service-stop/entry.ps1`

Impact:

- the current process/service management ingredient surface is incomplete for the project's stated reversibility requirement
- a later recipe failure can still leave stopped processes or services in drift if those ingredients are used directly

### AUD-014 Resolved: Window-cycle activation now survives the domain-thin rewrite in the standalone surface

The active window ingredient now delegates through the domain without losing the required support helpers at runtime.

Evidence:

- `src/ParsecEventExecutor/Private/Domains/window/entry.ps1`
- `src/ParsecEventExecutor/Private/Ingredients/window-cycle-activation/entry.ps1`
- `tests/StandaloneIngredient.Tests.ps1`

Impact:

- the thin ingredient/domain split is now operational in the standalone surface
- live validation is still required before treating this ingredient as hardware-safe

### AUD-015 Resolved: Generic scaling dispatch now matches the active display-domain signatures

`display.set-scaling` no longer dispatches unsupported parameters into the display domain, and the executor-state/profile flows that rely on scaling and snapshot verification are passing again.

Evidence:

- `src/ParsecEventExecutor/Private/Domains/display/entry.ps1`
- `src/ParsecEventExecutor/Private/Domains/display/Domain.ps1`
- `tests/ExecutorState.Tests.ps1`
- `tests/Profile.Tests.ps1`

Impact:

- scaling dispatch is no longer a known runtime blocker in the targeted suites
- broader live scaling validation is still required

### AUD-016 Medium: Personalization capability remains underexposed as concrete ingredients for wallpaper and background persistence

The personalization platform can capture and apply wallpaper, tiling, and background color state, and snapshot restore composes that capability, but the active concrete ingredient surface still exposes only `system.set-theme`.

Evidence:

- `src/ParsecEventExecutor/Private/Domains/personalization/Platform.ps1`
- `src/ParsecEventExecutor/Private/Domains/snapshot/Snapshot.Domain.ps1`
- `src/ParsecEventExecutor/Private/Ingredients/system-set-theme/schema.toml`

Impact:

- the project requirement around customization persistence is only partially exposed as first-class ingredient capability
- wallpaper/background persistence currently depends on snapshot flows instead of a dedicated reversible ingredient surface

### AUD-017 Resolved In Targeted Wiring Batch: command-domain bootstrap no longer fails on its internal support loader

The command domain no longer depends on an unavailable support-loader closure in its runtime path.

Evidence:

- `src/ParsecEventExecutor/Private/Domains/command/entry.ps1`
- `src/ParsecEventExecutor/Private/Ingredients/command-invoke/entry.ps1`
- targeted runtime repair in this cycle

Impact:

- the command-domain entry pattern is no longer a known targeted wiring failure
- the aggregate ingredient suite still needs a fresh full rerun before this can be treated as globally closed

### AUD-018 Resolved In Targeted Wiring Batch: `system.set-theme` no longer fails on personalization-domain support loading

The personalization domain now loads its support files into the active runtime path correctly, and the targeted snapshot/profile surfaces that depend on theme capture are passing again.

Evidence:

- `src/ParsecEventExecutor/Private/Domains/personalization/entry.ps1`
- `src/ParsecEventExecutor/Private/Ingredients/system-set-theme/entry.ps1`
- `tests/Profile.Tests.ps1`

Impact:

- personalization bootstrap is no longer a known targeted runtime blocker
- the broader aggregate ingredient suite still needs a fresh rerun to confirm closure across every surface

### AUD-019 Resolved In Targeted Wiring Batch: Service-domain dispatch no longer depends on cached scriptblocks that bypass test isolation

The service domain now dispatches through direct functions instead of cached scriptblocks, which removes the loader pattern that previously bypassed test interception.

Evidence:

- `src/ParsecEventExecutor/Private/Domains/service/lib.ps1`
- targeted runtime repair in this cycle

Impact:

- the service-domain bootstrap is simpler and more testable
- the aggregate ingredient suite still needs a fresh rerun before this item can be treated as fully closed

### AUD-020 Resolved In Targeted Wiring Batch: The active-display ingredient test harness now aligns with the module-backed display adapter path

The earlier targeted failure was traced to adapter-scope drift in the test harness rather than a confirmed active-display runtime defect.

Evidence:

- `tests/IngredientTestSupport.ps1`
- `tests/Profile.Tests.ps1`
- `tests/ExecutorState.Tests.ps1`

Impact:

- this is no longer a confirmed targeted runtime blocker
- active-display control remains high risk until live restore validation is completed

### AUD-023 Medium: Token-backed `process.start` reset still has one unresolved standalone assertion

The targeted standalone suite is down to one remaining failure. Token-backed reset for `process.start` returns `Succeeded`, but the current standalone assertion still cannot prove that the persisted `process_id` is being consumed through the expected lookup path.

Evidence:

- `tests/StandaloneIngredient.Tests.ps1`
- `src/ParsecEventExecutor/Private/IngredientInvocation.ps1`
- `src/ParsecEventExecutor/Private/Domains/process/entry.ps1`

Impact:

- this does not currently block the broader migration batch
- it remains a cleanup item for either stricter runtime confirmation or a less brittle test contract

### AUD-021 Medium: Process and service management still lack restart as a first-class ingredient capability

The active concrete management surface currently includes `process.start`, `process.stop`, `service.start`, and `service.stop`, but no restart ingredient exists for either processes or services.

Evidence:

- active ingredient packages under `src/ParsecEventExecutor/Private/Ingredients`
- `src/ParsecEventExecutor/Private/Ingredients/process-start/schema.toml`
- `src/ParsecEventExecutor/Private/Ingredients/process-stop/schema.toml`
- `src/ParsecEventExecutor/Private/Ingredients/service-start/schema.toml`
- `src/ParsecEventExecutor/Private/Ingredients/service-stop/schema.toml`

Impact:

- the project requirement for shell application service management is only partially exposed as first-class ingredient capability
- restart flows currently require composition or ad hoc recipe logic rather than a dedicated reversible management ingredient

### AUD-022 Medium: Audio playback endpoint handling is missing both restore-critical coverage and explicit domain ownership

Monitor activation and deactivation can change the active playback endpoint when displays expose associated audio devices. The current audit surface does not show any explicit `sound` domain, audio-prefixed ingredient surface, snapshot field, or test coverage for capturing the original playback device and restoring it after display-topology changes.

Evidence:

- the active architecture is domain-driven and uses domain-prefixed ingredient names
- active domains are currently `command`, `display`, `nvidia`, `personalization`, `process`, `service`, `snapshot`, and `window`
- there is no current `sound` domain or audio-prefixed ingredient surface
- the existing restore-critical ingredient surface focuses on display, scaling, process/service, snapshot, theme, and window behavior

Impact:

- display rollback may restore monitor topology while still leaving the machine on the wrong playback endpoint
- audio endpoint handling currently lacks a clear ownership boundary in the architecture
- this capability should likely live in a dedicated `sound` domain with first-class reversible ingredients such as `sound.set-playback-device`

## Recommended Next Actions

1. Run a dedicated live restore audit for:
   - `display.set-enabled`
   - `display.set-activedisplays`
   - `display.set-primary`
   - `display.persist-topology`
   - `display.snapshot reset`
2. Add reversible `reset` behavior for `process.stop` and `service.stop`, or replace them with explicitly reversible management ingredients that satisfy the project contract.
3. Resolve the remaining `process.start` token-reset assertion drift and confirm whether the runtime or the test contract should own the final fix.
4. Decide whether wallpaper/background persistence should remain snapshot-only or be promoted into a dedicated personalization ingredient.
5. Split the display domain internally before it becomes the next maintainability monolith.
6. Expose a reliable live audit command for scale and text-scale so rollback drift can be verified directly.
7. Update `README.md` and any stale public docs to remove compatibility-era wording.
8. Rerun the broader aggregate ingredient suite to confirm that the targeted wiring repairs hold across every ingredient entrypoint.
9. Decide whether restart should be promoted into dedicated `process.restart` and `service.restart` ingredients instead of remaining recipe-composed behavior.
10. Introduce a dedicated `sound` domain and decide which first-class reversible ingredients it should expose, then add capture/apply/verify/reset coverage for the default playback device rather than embedding audio endpoint restore implicitly inside unrelated topology flows.

## References

- [`docs/adr/2026-03-13-modular-ingredient-architecture.md`](../adr/2026-03-13-modular-ingredient-architecture.md)
- [`docs/plan/2026-03-13-modular-ingredient-architecture.md`](../plan/2026-03-13-modular-ingredient-architecture.md)
- [`docs/research/06-modular-ingredient-architecture/research.md`](../research/06-modular-ingredient-architecture/research.md)
