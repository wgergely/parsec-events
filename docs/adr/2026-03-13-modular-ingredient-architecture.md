# ADR: Modular Ingredient Architecture

**Date**: 2026-03-13
**Status**: Accepted

## Context

The current ingredient execution model is centered on [`IngredientRuntime.ps1`](../../src/ParsecEventExecutor/Private/IngredientRuntime.ps1), but that file is not only runtime infrastructure. It currently owns:

- ingredient definition and schema validation
- ingredient dispatch and loader behavior
- display interop and display topology behavior
- personalization behavior
- process and service capture behavior
- snapshot reset behavior

At the same time, the repository already has per-ingredient folders under [`src/ParsecEventExecutor/Private/Ingredients`](../../src/ParsecEventExecutor/Private/Ingredients), but those folders are not the real ownership boundary. Ingredient modules are loaded by dot-sourcing `lib.ps1`, promoting functions into `script:` scope, and then depending on centralized helper functions from the monolith.

Supporting research is recorded in [`docs/research/06-modular-ingredient-architecture/research.md`](../research/06-modular-ingredient-architecture/research.md).

## Why

The current architecture is unmaintainable because it collapses three separate concerns into one file:

- runtime-core concerns
- shared domain capability concerns
- concrete ingredient concerns

This has four concrete costs:

1. shared behavior has no clear ownership boundary
2. ingredient folders do not actually own ingredient implementation
3. PowerShell script-scope promotion creates implicit coupling
4. adding new ingredients encourages more growth in the monolith instead of growth in bounded modules

The codebase already shows natural domain seams, especially around display behavior. The architecture should align with those seams instead of centralizing them in a global runtime file.

## What

Adopt a three-layer architecture:

1. `runtime-core`
   Owns registration, schema validation, dispatch, orchestration, and package loading.

2. `domain modules`
   Own reusable capability code grouped by technical domain, such as:
   - `display`
   - `personalization`
   - `nvidia`
   - `process`
   - `service`
   - `snapshot`

3. `concrete ingredients`
   Own ingredient-specific schema and operation handlers. A concrete ingredient composes its owning domain rather than reaching into monolithic helpers or other ingredients.

The initial reference model is:

- `display` becomes the shared root for reusable display capability code
- concrete `display.*` ingredients become consumers of the `display` domain API

## Decision

Replace the monolithic ingredient runtime model with a `runtime-core + domain + ingredient` architecture.

Rules:

- `runtime-core` must not contain domain-specific behavior
- shared reusable behavior must live in the owning domain module
- concrete ingredients must not depend on other concrete ingredients for shared behavior
- ingredient loading must not rely on script-scope function promotion as the integration contract
- the existing umbrella ADR remains historical context; this decision is recorded as a separate date-prefixed ADR

## Blast Radius

This decision changes the internal architecture of the executor broadly.

Affected areas:

- ingredient loading
- ingredient registration
- ingredient dispatch boundaries
- shared display-related helpers
- personalization helpers
- NVIDIA capability integration
- process and service capture helpers
- snapshot support that currently lives in the monolith
- documentation and implementation planning that currently refer to the monolithic runtime

Unaffected at the decision level:

- the high-level recipe and ingredient vocabulary
- the need for snapshot-oriented execution
- the broader project goal of Parsec-triggered desktop/mobile transitions

## Positive Outcomes

- shared code has a clear owner
- concrete ingredients become smaller and easier to reason about
- domain reuse replaces ad hoc reuse through the monolith
- adding a new ingredient no longer requires growing a single global file
- the architecture becomes documentable as stable layers rather than a large implicit runtime
- the future implementation plan can reference domain boundaries directly

## Negative Outcomes

- the rewrite is invasive and touches most ingredient-adjacent internals
- the project introduces a new architectural term, `domain`, that is not yet live in the codebase
- some current helper flows that are convenient through global scope will need to be re-expressed with explicit boundaries
- the documentation surface now needs to distinguish historical research from the new architecture target

## Implementation Difficulty

**Difficulty**: High

Reason:

- the monolith currently owns multiple layers of behavior
- ingredient loading is coupled to PowerShell scope manipulation
- display capability code is deeply interleaved with runtime concerns
- snapshot and personalization behavior cross domain boundaries and will need deliberate placement

The difficulty is architectural rather than conceptual. The domain seams are visible; the work is in extracting them cleanly.

## Reasoning

This decision was chosen over four alternatives:

### 1. Keep extending the monolithic runtime

Rejected because it preserves the current ownership failure. New capabilities would continue to accumulate in a single file.

### 2. Keep ingredients isolated but duplicate shared behavior

Rejected because display-related ingredients already demonstrate genuine shared technical behavior. Duplicating that behavior would trade one maintenance problem for another.

### 3. Reuse behavior directly across concrete ingredients

Rejected because cross-ingredient reuse obscures ownership and turns concrete ingredients into informal base libraries.

### 4. Continue using implicit script-scope sharing

Rejected because dot-sourcing and promoting functions into `script:` scope makes the integration boundary implicit, fragile, and difficult to document.

The selected model keeps reuse where it is real, but contains that reuse inside explicit domain modules. Concrete ingredients remain concrete. The runtime remains runtime-core.

## References

### Primary supporting research

- [`docs/research/06-modular-ingredient-architecture/research.md`](../research/06-modular-ingredient-architecture/research.md)

### Local code evidence

- [`src/ParsecEventExecutor/Private/IngredientRuntime.ps1`](../../src/ParsecEventExecutor/Private/IngredientRuntime.ps1)
- [`src/ParsecEventExecutor/Private/Ingredients/display-set-resolution/lib.ps1`](../../src/ParsecEventExecutor/Private/Ingredients/display-set-resolution/lib.ps1)
- [`src/ParsecEventExecutor/Private/Ingredients/display-ensure-resolution/lib.ps1`](../../src/ParsecEventExecutor/Private/Ingredients/display-ensure-resolution/lib.ps1)
- [`src/ParsecEventExecutor/ParsecEventExecutor.psm1`](../../src/ParsecEventExecutor/ParsecEventExecutor.psm1)

### Historical context

- [`docs/adr/ADR.md`](ADR.md)
- [`docs/plan/2026-03-13-modular-ingredient-architecture.md`](../plan/2026-03-13-modular-ingredient-architecture.md)
