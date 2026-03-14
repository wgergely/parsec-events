# Modular Ingredient Architecture Audit

Topic: Modular ingredient architecture audit after the core/domain/ingredient rewrite

Audit Surface: `src/ParsecEventExecutor`, `tests`, `recipes`, `docs/adr/2026-03-13-modular-ingredient-architecture.md`, `docs/plan/2026-03-13-modular-ingredient-architecture.md`, `docs/research/06-modular-ingredient-architecture/research.md`

Rewrite Scope: Identify remaining regressions, misses, skips, stubs, and legacy behaviors after the modular rewrite; persist current development state, testing status, live-validation status, and an assessment of event chaining.

## Summary

The monolithic runtime has been retired from the live path, and the modular `Core + Domains + Ingredients` architecture is active. The current runtime is functional enough to load ingredients lazily, execute standalone ingredients, and execute recipes through the new executor.

The rewrite is not fully complete from an architectural perspective. The main remaining gaps are:

- domain ownership is still inferred instead of declared in ingredient manifests
- live restore fidelity for real display topology changes is still not trustworthy
- recipe compensation is step-local rather than chain-wide
- event chaining is implemented and tested, but it is still a linear dependency-gated executor rather than a true dependency scheduler
- some domain boundaries still leak or duplicate behavior

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
| `tests/StandaloneIngredient.Tests.ps1` | `30 passed, 0 failed, 0 skipped` | 2026-03-14 | Full standalone ingredient suite passed in `1544s` |
| `tests/Executor.Tests.ps1` + `tests/RecipeParsing.Tests.ps1` | `21 passed, 0 failed, 0 skipped` | 2026-03-14 | Recipe parsing and executor flow passed in `174.92s` |

### Test-surface observations

- No active `skip`, `xfail`, or pending test markers were found in `tests`.
- The current tests are not stubbed out of existence; the executor and standalone ingredient surfaces are both exercised.
- The green test state does not yet prove that all live display restore paths are correct on real hardware.

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

What is implemented:

- ordered step execution
- `depends_on` gating
- `mode_is` conditional execution
- retries
- readiness checks
- verification
- active snapshot propagation
- executor/run persistence
- step-local compensation via `reset`

What is not implemented:

- true dependency scheduling or graph execution
- cycle detection for recipe dependencies
- chain-wide reverse rollback of previously successful steps when a later step fails

Assessment:

- The event-chaining mechanism is functional and test-backed.
- It should currently be described as a linear dependency-gated executor, not as a full dependency-graph engine.

## Findings

### AUD-001 High: Ingredient manifests still do not declare their domain explicitly

Every ingredient `schema.toml` currently omits `domain = ...`. Domain ownership is still inferred from naming and folder structure instead of being declared by manifest contract.

Evidence:

- all files under `src/ParsecEventExecutor/Private/Ingredients/*/schema.toml` were checked and none contained a `domain =` declaration

Impact:

- this violates the intended manifest-driven architecture
- loader behavior still depends on convention rather than explicit package metadata

### AUD-002 High: Live restore fidelity remains unproven and a real regression has already been observed

The latest live audit state still shows monitor 3 disabled after test execution, while the user-reported expected desktop baseline requires it to be enabled.

Evidence:

- direct live `Get-ParsecDisplay` observation on 2026-03-14
- user-reported restore regression: monitor 3 did not come back

Impact:

- snapshot and token-based reset cannot yet be treated as trustworthy on real hardware
- topology-changing ingredients remain high risk until live restore validation is completed

### AUD-003 High: Recipe compensation is step-local, not chain-wide

The executor compensates the current failed step when policy is `explicit` and `reset` is supported, but it does not unwind already successful earlier steps in reverse order after a later step failure.

Evidence:

- `src/ParsecEventExecutor/Private/Execution.ps1`
- `tests/Executor.Tests.ps1`

Impact:

- multi-step event flows can still leave the desktop in drift if a later step fails after earlier steps succeeded
- this is directly relevant to enter-mobile and return-desktop reliability

### AUD-004 Medium: Event chaining is linear and dependency-gated, not a true graph scheduler

`depends_on` is implemented as blocking logic in the linear executor. There is no evidence of dependency graph construction, topological ordering, or cycle detection.

Evidence:

- `src/ParsecEventExecutor/Private/Execution.ps1`
- no scheduler/graph/cycle handling was found in the runtime

Impact:

- the executor is functional, but its architecture is narrower than a true dependency engine
- dependency mistakes may only surface at runtime as blocked steps rather than being rejected structurally

### AUD-005 Medium: Core still owns the shared observed-state bridge

Domains still call `Get-ParsecObservedState`, which currently lives in `src/ParsecEventExecutor/Private/Core/StateHelpers.ps1`. This keeps an important capability bridge in core instead of pushing state observation fully behind domain APIs.

Evidence:

- `src/ParsecEventExecutor/Private/Core/StateHelpers.ps1`
- `src/ParsecEventExecutor/Private/Domains/nvidia/lib.ps1`
- `src/ParsecEventExecutor/Private/Domains/personalization/Personalization.Domain.ps1`
- `src/ParsecEventExecutor/Private/Domains/snapshot/Snapshot.Domain.ps1`
- `src/ParsecEventExecutor/Private/IngredientInvocation.ps1`

Impact:

- the old mixed-runtime instinct still survives in one shared bridge
- this weakens strict domain ownership

### AUD-006 Medium: The window capability violates the intended domain-consumer split

`window.cycle-activation` still appears to duplicate a substantial amount of behavior already present in the `window` domain entrypoint instead of remaining a thin concrete consumer of that domain.

Evidence:

- `src/ParsecEventExecutor/Private/Domains/window/entry.ps1`
- `src/ParsecEventExecutor/Private/Ingredients/window-cycle-activation/entry.ps1`

Impact:

- duplicated logic creates drift risk
- this is the clearest remaining example of the old pattern reappearing inside the new architecture

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

## Recommended Next Actions

1. Add explicit `domain = ...` declarations to every ingredient manifest and enforce them in the loader.
2. Run a dedicated live restore audit for:
   - `display.set-enabled`
   - `display.set-activedisplays`
   - `display.set-primary`
   - `display.persist-topology`
   - `display.snapshot reset`
3. Upgrade compensation from step-local reset to ordered chain-wide rollback for explicit-compensation recipes.
4. Decide whether the executor should remain linear or be upgraded into a true dependency-graph scheduler with cycle detection.
5. Move shared observed-state capture behind domain-owned APIs and remove the remaining core bridge.
6. Collapse duplicated `window` capability logic so the ingredient becomes a thin consumer of the domain.
7. Split the display domain internally before it becomes the next maintainability monolith.
8. Expose a reliable live audit command for scale and text-scale so rollback drift can be verified directly.
9. Update `README.md` and any stale public docs to remove compatibility-era wording.

## References

- [`docs/adr/2026-03-13-modular-ingredient-architecture.md`](../adr/2026-03-13-modular-ingredient-architecture.md)
- [`docs/plan/2026-03-13-modular-ingredient-architecture.md`](../plan/2026-03-13-modular-ingredient-architecture.md)
- [`docs/research/06-modular-ingredient-architecture/research.md`](../research/06-modular-ingredient-architecture/research.md)
