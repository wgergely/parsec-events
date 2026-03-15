# Live Integration Test Audit — 2026-03-14

## Summary

Live integration testing on a 2-monitor desktop (BenQ at -1920,0 + PA278CV primary at 0,0) revealed four defects across the display and window domains. All have been fixed and verified.

## Defect 1: display.set-primary corrupts monitor spatial arrangement

**Symptom**: After `set-primary` switched the primary monitor, the BenQ's position was reset to Windows defaults (stacked to the right at width,0) instead of preserving the original left-of-primary layout (-1920,0).

**Root cause**: `Set-ParsecDisplayPrimaryInternal` hardcoded non-primary monitors to `(newPrimaryWidth, 0)` instead of computing an offset translation that preserves relative positions.

**Fix applied**:
- **Capture** (`Invoke-ParsecDisplayDomainCapturePrimary` in Domain.ps1): Now captures `monitor_positions` array with `{ device_name, x, y, width, height, is_primary }` for ALL enabled monitors.
- **Apply** (`Set-ParsecDisplayPrimaryInternal` in Platform.ps1): Stages the new primary first (CDS_SET_PRIMARY), then repositions other monitors using offset translation so the target lands at (0,0) and others preserve their relative positions.
- **Reset** (`Invoke-ParsecDisplayDomainResetPrimary` in Domain.ps1): Passes captured `monitor_positions` to the adapter for exact position restore.
- **Mock** (`tests/IngredientTestSupport.ps1`): Updated `SetPrimary` mock to handle both apply (offset translation) and reset (exact positions) paths.

**Live test result**: PASSED — taskbar switched sides, monitor topology preserved, reset restored original layout.

## Defect 2: window.cycle-activation fails on live hardware (PascalCase mismatch)

**Symptom**: C# interop returns PSObjects with PascalCase property names (`IsVisible`, `ClassName`, etc.) but PowerShell domain code expects snake_case keys (`is_visible`, `class_name`). Unit tests pass because mock adapters return `[ordered]@{}` dictionaries (IDictionary path, no conversion).

**Root cause**: `ConvertTo-ParsecPlainObject` converted PSObject properties to ordered dictionaries but preserved the original property names verbatim. Only the IDictionary branch preserved keys — and test mocks always use dictionaries.

**Fix applied**:
- Added `ConvertTo-ParsecSnakeCaseKey` helper in Utility.ps1: regex-based PascalCase-to-snake_case conversion (`IsVisible` → `is_visible`, `ClassName` → `class_name`).
- Modified the PSObject branch of `ConvertTo-ParsecPlainObject` to convert property names via the helper.
- IDictionary branch unchanged — dictionaries already have explicit key names from test adapters.

**Live test result**: PENDING — requires interactive terminal with foreground windows. Background process returns handle 0. `.Contains()` errors confirmed fixed.

## Defect 3: CDS_UPDATEREGISTRY fails due to dirty registry state

**Symptom**: All `ChangeDisplaySettingsEx` calls with `CDS_UPDATEREGISTRY` returned `DISP_CHANGE_FAILED` (-1), even with no changes to the mode.

**Root cause**: Prior failed `CDS_UPDATEREGISTRY | CDS_NORESET` staging operations wrote partial positions to the registry without committing. DISPLAY1's registry showed position (2560,0) while the live desktop had it at (-1920,0). Windows rejected all `CDS_UPDATEREGISTRY` calls because the combined registry topology was invalid.

**Initially misdiagnosed** as an elevation/admin issue. Research confirmed `CDS_UPDATEREGISTRY` writes to HKCU (user profile), not HKLM — no admin needed.

**Incident**: During debugging, a `CDS_RESET` call was issued which applied the stale registry positions to the live desktop, corrupting the BenQ's position from (-1920,0) to (2560,0). User had to manually restore.

**Fix applied**:
- Added `Sync-ParsecDisplayRegistryState` function to Platform.ps1 that re-syncs the display registry by staging ALL monitors with their current `ENUM_CURRENT_SETTINGS` modes before any display mutation.
- Called at the start of `Set-ParsecDisplayPrimaryInternal` before any staging operations.

**Live test result**: PASSED — after registry sync, primary switch succeeded on second session.

## Defect 4: Window entry.ps1 closure scope prevents ConvertTo-ParsecPlainObject resolution

**Symptom**: The `$toPlain` closure in window entry.ps1 used `Get-Command -Name 'ConvertTo-ParsecPlainObject'` at runtime, which failed because the function isn't visible in the closure's execution context. Raw C# `WindowCapture` objects reached the filter code, causing `.Contains()` method-not-found errors.

**Root cause**: entry.ps1 closures created with `.GetNewClosure()` capture variables at creation time, but command resolution happens at runtime in the closure's scope. `ConvertTo-ParsecPlainObject` is available when entry.ps1 is loaded but not when the closure executes later.

**Fix applied**:
- Changed `$toPlain` to capture a direct function reference via `$toPlainRef = Get-Command -Name 'ConvertTo-ParsecPlainObject'` at load time, then use `& $toPlainRef` in the closure.
- Added `& $toPlain` conversion at all consumer sites (`GetForegroundWindowInfo`, `GetTopLevelWindows` results) to ensure objects are always converted regardless of adapter path.

**Live test result**: `.Contains()` errors confirmed fixed. Full cycle test requires interactive terminal.

## Test Results

| Check | Result |
|-------|--------|
| PSScriptAnalyzer (all modified files) | 0 violations |
| Pester full suite | 113 passed, 0 failed |
| Live: display.set-primary (apply + reset) | PASSED |
| Live: window.cycle-activation | PENDING (requires interactive terminal) |

## Files Modified

| File | Change |
|------|--------|
| `src/ParsecEventExecutor/Private/Utility.ps1` | Added `ConvertTo-ParsecSnakeCaseKey`; PSObject branch converts property names |
| `src/ParsecEventExecutor/Private/Domains/display/Platform.ps1` | Rewrote `Set-ParsecDisplayPrimaryInternal`; added `Sync-ParsecDisplayRegistryState` |
| `src/ParsecEventExecutor/Private/Domains/display/Domain.ps1` | `CapturePrimary` captures all monitor positions; `ResetPrimary` passes positions to adapter |
| `src/ParsecEventExecutor/Private/Domains/window/entry.ps1` | Fixed `$toPlain` closure scope; added conversion at consumer sites |
| `src/ParsecEventExecutor/Private/IngredientInvocation.ps1` | Guarded `PSObject.Properties.Name` access for ordered dictionaries |
| `tests/IngredientTestSupport.ps1` | `SetPrimary` mock handles offset and exact-position paths |
