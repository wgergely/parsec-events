# Execution Plan: ADR-Enforced Core/Domain/Ingredient Rewrite

## Summary

Implement the architecture defined in [2026-03-13-modular-ingredient-architecture.md](/Y:/code/parsec-events-worktrees/feature-live-recipe/docs/adr/2026-03-13-modular-ingredient-architecture.md) and grounded by [research.md](/Y:/code/parsec-events-worktrees/feature-live-recipe/docs/research/06-modular-ingredient-architecture/research.md).

The first implementation action is mandatory and exact:

- overwrite [implementation-plan.md](/Y:/code/parsec-events-worktrees/feature-live-recipe/docs/plan/implementation-plan.md) with the exact plan text from the previously approved `<proposed_plan>` block, verbatim in substance, so the plan becomes the persisted execution parent under `docs/plan`

After that, execute as a clean-break rewrite with these invariants:

- `Core` owns loading, registration, schema validation, dispatch, orchestration, readiness/retry flow, and persistence
- `Domains` own shared technical capability code
- `Ingredients` own concrete schema plus operation handlers and consume declared domain APIs
- no backward compatibility layer
- no mixed old/new runtime
- no cross-ingredient reuse for shared behavior
- no script-scope promotion or `Function:` scraping
- the ADR and persisted plan are authoritative and must be enforced during implementation

## Implementation Changes

### 1. Persist and align documentation first

- replace the current stale [implementation-plan.md](/Y:/code/parsec-events-worktrees/feature-live-recipe/docs/plan/implementation-plan.md) with the approved rewrite plan before any code edits
- treat the ADR and plan as the parent constraints for all later code decisions
- if current code or tests contradict the ADR, the ADR wins unless a new ADR is written

### 2. Define the new runtime contracts before moving code

Implement the new contracts first so every later refactor has a target:

- ingredient definition object with:
  - `name`
  - `domain`
  - `kind`
  - `operations`
  - `operation_schemas`
  - capability requirements
- operation handler signature:
  - `param($ctx, $args, $prior)`
- runtime `ctx` surface containing:
  - execution metadata
  - logging
  - result construction
  - persistence/state access
  - owning domain API handle
- domain package contract:
  - one public API surface per domain
  - no exposure of private helpers or file layout
  - no direct dependency on concrete ingredients

Do not preserve `Get-ParsecIngredientOperations` or the old `schema.toml + lib.ps1 + script-scope` loading contract unless the new loader intentionally consumes compatible manifests without inheriting the old coupling model.

### 3. Build the new structure and loader

Create the new structure under `src/ParsecEventExecutor/Private`:

- `Core/`
- `Domains/`
- `Ingredients/`

Implement loading order as:

1. root module loads `Core`
2. `Core` loads domains
3. `Core` loads ingredients
4. ingredients register by returning definition objects
5. `Core` builds the registry from those definitions

Hard rules:

- no `Function:\script:` promotion
- no `Get-ChildItem Function:`
- no ambient function discovery
- no concrete ingredient calling another concrete ingredient for shared behavior

### 4. Extract domains from the monolith by ownership

Re-home code from `IngredientRuntime.ps1` into these domains:

- `display`
  - display interop bootstrap
  - observed display state capture
  - monitor targeting
  - supported mode lookup
  - resolution/orientation/primary/enabled primitives
  - topology compare and topology reset
- `personalization`
  - theme
  - wallpaper
  - text scale
  - UI scale
- `nvidia`
  - NVIDIA adapter bootstrap and custom-resolution primitives
- `process`
  - process capture/state primitives
- `service`
  - service capture/state primitives
- `snapshot`
  - snapshot naming and reset behavior composed from `display` and `personalization`
- `core`
  - definition creation
  - schema validation
  - operation support checks
  - dispatch
  - loader
  - orchestration and persistence

Ownership rule:

- reused by 2+ concrete ingredients in one area means domain code
- unique to one ingredient means ingredient-local code

### 5. Rebuild concrete ingredients domain-first

Use `display` as the reference domain and rebuild all `display.*` ingredients against it first.

First-wave ingredients:

- `display.set-resolution`
- `display.ensure-resolution`
- `display.set-orientation`
- `display.set-primary`
- `display.set-enabled`
- `display.set-activedisplays`
- `display.set-scaling`
- `display.set-textscale`
- `display.set-uiscale`
- `display.persist-topology`
- `display.snapshot`

Concrete ingredient rules:

- schema remains local to the ingredient package
- ingredient code may call only:
  - its owning domain API
  - runtime `ctx`
- no direct use of monolithic helpers
- no ingredient-to-ingredient orchestration shortcuts
- `display.ensure-resolution` must stop calling `display.set-resolution` and instead consume `display` domain primitives directly

Second wave:

- `system.set-theme` against `personalization`
- `nvidia.add-custom-resolution` against `nvidia`, with explicit `display` dependency only if required by the contract
- `process.*` against `process`
- `service.*` against `service`
- `window.cycle-activation` becomes either:
  - a small `window` domain if reuse is justified, or
  - a standalone ingredient package with no false shared abstraction

Default decision:
- keep `window.cycle-activation` standalone unless a second window-focused ingredient appears during implementation

### 6. Rebuild orchestration on the new contracts only

Keep existing runtime nouns where still valid:

- `recipe`
- `ingredient`
- `operation`
- `readiness`
- `snapshot`

Core remains responsible for:

- sequencing `capture/apply/verify/wait/reset`
- retries
- readiness probing
- compensation
- invocation/token persistence
- run-state handling

Ingredients remain capability implementations only.

### 7. Delete the monolith and stale architecture last

After all target domains and ingredients are rebuilt:

- remove `IngredientRuntime.ps1`
- remove obsolete helpers displaced by domains
- remove stale loader assumptions from the root module
- correct stale documentation references such as `Private/Ingredients.ps1`

## Delegation Strategy

Use an orchestrator model during implementation.

### Main orchestrator responsibilities

- enforce ADR and persisted plan
- own cross-cutting contracts
- review all worker outputs for drift
- resolve integration mismatches
- handle any architectural ambiguity directly instead of letting it spread

### Delegate to workers where the write sets are disjoint

Worker 1:
- `Core` loader, registry, schema validation, dispatcher contracts

Worker 2:
- `display` domain extraction and first-wave `display.*` ingredient rebuilds

Worker 3:
- `personalization` and `snapshot` domains plus related ingredients

Worker 4:
- `nvidia`, `process`, and `service` domains plus related ingredients

Worker 5:
- test adaptation and integration coverage once the new contracts are stable

Delegation rules:

- each worker owns a disjoint file/module area
- no worker reverts another worker’s edits
- repetitive ingredient rewrites should be delegated, not done centrally
- the orchestrator steps in for:
  - contract drift
  - cross-domain boundary decisions
  - failures to follow the ADR
  - integration bugs

## Public APIs / Interfaces / Types

The implementation must lock these interfaces:

- ingredient definition object
- operation handler signature `param($ctx, $args, $prior)`
- runtime context `ctx`
- domain public API object
- dependency direction:
  - `Core -> Domains -> Ingredients`
  - `Ingredients -> owning Domain API`
  - no `Ingredient -> Ingredient`
  - no `Ingredient -> Core internals`
  - cross-domain access only when declared and intentionally supported

## Test Plan

### Contract tests

- loader registers domains and ingredients without script-scope promotion
- invalid manifests fail with precise errors
- ingredients cannot register without a valid declared domain
- handlers receive the expected `ctx`, `args`, and `prior` shape

### Domain tests

- `display` domain covers targeting, capture, supported-mode lookup, topology compare, and reset
- `personalization` covers theme, wallpaper, text scale, and UI scale
- `nvidia`, `process`, `service`, and `snapshot` each have direct public-API tests

### Ingredient tests

- every rebuilt ingredient verifies schema, apply, verify, wait where applicable, and reset
- `display.ensure-resolution` no longer calls `display.set-resolution`
- snapshot behavior composes through domains rather than monolithic helpers

### Integration tests

- recipe execution still supports dependency ordering, readiness probes, verification, retries, and explicit compensation
- invocation/token persistence still records results and reset paths through the new core
- snapshot-oriented execution remains the active behavioral model

### Regression checks

- no remaining runtime dependency on `IngredientRuntime.ps1`
- no remaining use of `Get-ChildItem Function:` or `Function:\script:`
- no remaining cross-ingredient shared-behavior reuse

## Assumptions

- [2026-03-13-modular-ingredient-architecture.md](/Y:/code/parsec-events-worktrees/feature-live-recipe/docs/adr/2026-03-13-modular-ingredient-architecture.md) is the governing architectural parent
- [research.md](/Y:/code/parsec-events-worktrees/feature-live-recipe/docs/research/06-modular-ingredient-architecture/research.md) is the evidence base for current-state problems and domain mapping
- `display` is the first reference domain
- backward compatibility, temporary runability, and mixed-runtime migration are out of scope
- the first implementation action is to persist this plan into [implementation-plan.md](/Y:/code/parsec-events-worktrees/feature-live-recipe/docs/plan/implementation-plan.md) before any code changes
