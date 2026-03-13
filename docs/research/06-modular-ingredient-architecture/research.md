# Modular Ingredient Architecture Research

**Date**: 2026-03-13
**Status**: Supporting research for [`2026-03-13-modular-ingredient-architecture.md`](../../adr/2026-03-13-modular-ingredient-architecture.md)

## Topic

Ground the decision to replace the monolithic ingredient runtime with a layered `runtime-core + domain + ingredient` architecture.

## Audit Surface

- [`src/ParsecEventExecutor/Private/IngredientRuntime.ps1`](../../../src/ParsecEventExecutor/Private/IngredientRuntime.ps1)
- [`src/ParsecEventExecutor/Private/Ingredients/display-set-resolution/lib.ps1`](../../../src/ParsecEventExecutor/Private/Ingredients/display-set-resolution/lib.ps1)
- [`src/ParsecEventExecutor/Private/Ingredients/display-ensure-resolution/lib.ps1`](../../../src/ParsecEventExecutor/Private/Ingredients/display-ensure-resolution/lib.ps1)
- [`docs/plan/2026-03-13-modular-ingredient-architecture.md`](../../plan/2026-03-13-modular-ingredient-architecture.md)
- [`docs/adr/ADR.md`](../../adr/ADR.md)

## Findings

### 1. `IngredientRuntime.ps1` mixes multiple architectural layers

The current runtime file is not only a registry and dispatch surface. It also owns domain and capability behavior.

Evidence:

- Runtime-core concerns appear at the top of the file through ingredient definition creation and schema validation.
- Display interop is initialized in `Initialize-ParsecDisplayInterop`.
- Personalization interop is initialized in `Initialize-ParsecPersonalizationInterop`.
- Display topology restoration is implemented in `Invoke-ParsecDisplayTopologyReset`.
- Process and service capture helpers are implemented in `Get-ParsecProcessCaptureResult` and `Get-ParsecServiceCaptureResult`.
- Snapshot restoration is implemented in `Invoke-ParsecSnapshotReset`.
- Ingredient dispatch and ingredient loading are implemented in `Invoke-ParsecIngredientOperation`, `Import-ParsecIngredientModule`, and `Initialize-ParsecIngredientRegistry`.

Representative anchors:

- [`IngredientRuntime.ps1:1`](../../../src/ParsecEventExecutor/Private/IngredientRuntime.ps1#L1)
- [`IngredientRuntime.ps1:199`](../../../src/ParsecEventExecutor/Private/IngredientRuntime.ps1#L199)
- [`IngredientRuntime.ps1:1809`](../../../src/ParsecEventExecutor/Private/IngredientRuntime.ps1#L1809)
- [`IngredientRuntime.ps1:2557`](../../../src/ParsecEventExecutor/Private/IngredientRuntime.ps1#L2557)
- [`IngredientRuntime.ps1:2963`](../../../src/ParsecEventExecutor/Private/IngredientRuntime.ps1#L2963)
- [`IngredientRuntime.ps1:3007`](../../../src/ParsecEventExecutor/Private/IngredientRuntime.ps1#L3007)
- [`IngredientRuntime.ps1:3364`](../../../src/ParsecEventExecutor/Private/IngredientRuntime.ps1#L3364)
- [`IngredientRuntime.ps1:3411`](../../../src/ParsecEventExecutor/Private/IngredientRuntime.ps1#L3411)
- [`IngredientRuntime.ps1:3561`](../../../src/ParsecEventExecutor/Private/IngredientRuntime.ps1#L3561)
- [`IngredientRuntime.ps1:3594`](../../../src/ParsecEventExecutor/Private/IngredientRuntime.ps1#L3594)

### 2. Ingredient folders exist, but they are not the ownership boundary

The repository already stores ingredients in dedicated folders, but those folders do not fully own ingredient behavior.

Evidence:

- The loader dot-sources each ingredient `lib.ps1`, inspects `Function:`, and promotes discovered functions into `script:` scope during import.
- Concrete display ingredients depend on centralized helpers such as observed-state lookup, target resolution, supported-mode lookup, display capture, and display adapter calls.
- Some ingredients compose behavior by calling `Invoke-ParsecIngredientOperation`, which routes through the monolithic runtime rather than a bounded domain API.

Representative anchors:

- [`IngredientRuntime.ps1:3561`](../../../src/ParsecEventExecutor/Private/IngredientRuntime.ps1#L3561)
- [`IngredientRuntime.ps1:3594`](../../../src/ParsecEventExecutor/Private/IngredientRuntime.ps1#L3594)
- [`display-set-resolution/lib.ps1:1`](../../../src/ParsecEventExecutor/Private/Ingredients/display-set-resolution/lib.ps1#L1)
- [`display-ensure-resolution/lib.ps1:1`](../../../src/ParsecEventExecutor/Private/Ingredients/display-ensure-resolution/lib.ps1#L1)

### 3. The current codebase already suggests a domain split

The monolith is not arbitrary. Its contents cluster into reusable technical domains that can be extracted without inventing new behavior.

Recommended mapping:

- `runtime-core`
  - ingredient definition
  - registration
  - schema validation
  - dispatch
  - loader
- `display`
  - display interop
  - observed-state capture
  - target resolution
  - target orientation
  - primary display changes
  - enable/disable logic
  - topology compare and reset
- `personalization`
  - theme state
  - wallpaper state
  - text scaling
  - UI scaling
- `nvidia`
  - NVIDIA adapter initialization
  - custom-resolution backend behavior
- `process`
  - process capture helpers
- `service`
  - service capture helpers
- `snapshot`
  - snapshot naming
  - snapshot target resolution
  - snapshot reset behavior

### 4. Concrete ingredients should become domain consumers

The display ingredients are the clearest example. They are concrete capabilities built on top of shared display behavior.

Evidence:

- `display.set-resolution` is a concrete ingredient, but its behavior is largely argument shaping and result handling around shared display operations.
- `display.ensure-resolution` uses the same display helpers and composes behavior across the same domain.

This supports a model where:

- the `display` domain owns shared display capability code
- concrete `display.*` ingredients declare schema and operations against that domain API

### 5. Documentation drift exists and should be contained

The supporting ADR should not try to rewrite historical documents. It should establish the new architecture cleanly and cite the drift where needed.

Evidence:

- [`docs/plan/2026-03-13-modular-ingredient-architecture.md`](../../plan/2026-03-13-modular-ingredient-architecture.md) is now the authoritative feature plan for this rewrite.
- [`docs/adr/ADR.md`](../../adr/ADR.md) acts as an umbrella ADR with multiple embedded decisions.
- Existing docs still contain profile-oriented framing, while the current implementation plan is snapshot-oriented.

## Constraints For The ADR

- Keep `ingredient`, `operation`, and `recipe` as the current execution nouns.
- Introduce `domain` as a new architectural layer above concrete ingredients and below runtime-core.
- Treat the new ADR as a separate, date-prefixed record instead of extending the umbrella ADR.
- Keep the ADR architecture-focused. It should not attempt to restate the full historical research set.

## References

- [`src/ParsecEventExecutor/Private/IngredientRuntime.ps1`](../../../src/ParsecEventExecutor/Private/IngredientRuntime.ps1)
- [`src/ParsecEventExecutor/Private/Ingredients/display-set-resolution/lib.ps1`](../../../src/ParsecEventExecutor/Private/Ingredients/display-set-resolution/lib.ps1)
- [`src/ParsecEventExecutor/Private/Ingredients/display-ensure-resolution/lib.ps1`](../../../src/ParsecEventExecutor/Private/Ingredients/display-ensure-resolution/lib.ps1)
- [`docs/plan/2026-03-13-modular-ingredient-architecture.md`](../../plan/2026-03-13-modular-ingredient-architecture.md)
- [`docs/adr/ADR.md`](../../adr/ADR.md)
