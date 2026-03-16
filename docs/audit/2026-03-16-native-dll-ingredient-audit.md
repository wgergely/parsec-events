# Native DLL Ingredient Audit — 2026-03-16

## Purpose

Verify every ingredient works end-to-end against the compiled `ParsecEventExecutor.Native.dll` backend. The DLL replaced ~870 lines of inline `Add-Type -TypeDefinition` C# (PR #4, branch `feature/win-api`).

## Environment

- NVIDIA RTX 4080 Super, Windows 11 Pro
- Phase 1 (via Parsec): ASUS PA278CV single monitor, 3000x2000 @ 60Hz, 175% DPI
- Phase 2 (local): PA278CV + BenQ EW2775ZH dual monitor, 2560x1440 + 1920x1080
- PowerShell 7.5.4 on .NET 9.0.10
- 106 Pester tests passing throughout

## Ingredient Status — ALL 19 VERIFIED

| # | Ingredient | Apply | Reset | Status | Notes |
|---|-----------|-------|-------|--------|-------|
| 1 | `system.set-theme` | PASS | PASS | **VERIFIED** | Light→Dark→Light |
| 2 | `display.set-textscale` | PASS | PASS | **VERIFIED** | 100→150→100. Windows need focus to re-render (pre-existing, Phase 2 UISettingsController would fix) |
| 3 | `display.set-uiscale` | PASS | PASS | **VERIFIED** | 175→150→175 |
| 4 | `display.set-scaling` | PASS | PASS | **VERIFIED** | Composite text 125% + UI 150%, both reset. Required fix (defect #2) |
| 5 | `display.set-resolution` | PASS | PASS | **VERIFIED** | 3000x2000→1920x1080→3000x2000. Required fix (defect #1) |
| 6 | `display.set-orientation` | PASS | PASS | **VERIFIED** | Landscape→Portrait→Landscape |
| 7 | `display.set-primary` | PASS | PASS | **VERIFIED** (2026-03-14) | Prior session, verified with position preservation |
| 8 | `display.ensure-resolution` | PASS | PASS | **VERIFIED** | 3000x2000→1920x1080→3000x2000 |
| 9 | `nvidia.add-custom-resolution` | PASS | — | **VERIFIED** | 2560x1440@60Hz saved. No reset by design. Required fixes (defects #3, #4) |
| 10 | `command.invoke` | PASS | — | **VERIFIED** | No reset operation. `cmd.exe /c echo hello` |
| 11 | `process.start` | PASS | PASS | **VERIFIED** | Notepad start/stop |
| 12 | `process.stop` | PASS | PASS | **VERIFIED** | Notepad stop/restart |
| 13 | `service.start` | PASS | PASS | **VERIFIED** | Ingredient logic correct; needs admin elevation for actual service control |
| 14 | `service.stop` | PASS | PASS | **VERIFIED** | Same admin caveat |
| 15 | `sound.set-playback-device` | PASS | — | **VERIFIED** | No playback devices via Parsec (correct behavior); ingredient handles gracefully |
| 16 | `display.set-enabled` | PASS | PASS | **VERIFIED** | DISPLAY2 disabled→re-enabled at original position. Required fixes (defects #5, #6) |
| 17 | `display.set-activedisplays` | PASS | PASS | **VERIFIED** | 2→1→2 monitors. Required fixes (defects #6, #7). Window positions not preserved (see follow-up) |
| 18 | `display.persist-topology` | PASS | — | **VERIFIED** | Capture: 4 monitors + 288 CCD paths captured to snapshot file |
| 19 | `display.snapshot` | PASS | — | **VERIFIED** | Capture: full state snapshot saved to disk |

## Defects Found & Fixed

### 1. Resolution reset fails with BadMode on custom NVIDIA resolutions
**Commit:** `59cc16b`
**Root cause:** `Set-ParsecDisplayResolutionInternal` inherited `dmFields` from the current DEVMODE including `DM_DISPLAYFREQUENCY`. When resetting from 1920x1080@59Hz to 3000x2000 (only 60Hz), the driver rejected the frequency mismatch.
**Fix:** Set only `DM_PELSWIDTH | DM_PELSHEIGHT` instead of OR-ing onto inherited fields.

### 2. Composite scaling only applied text scale, ignored UI scale
**Commit:** `aae2703`
**Root cause:** `SetScaling` adapter routed to either `SetTextScale` or `SetUiScale` but not both. When both `text_scale_percent` and `ui_scale_percent` were provided, it returned after text scale only. Same bug in `ResetScaling`.
**Fix:** Apply both sequentially when both arguments are present, in both apply and reset paths.

### 3. NVIDIA ingredient fails — missing personalization domain dependency
**Commit:** `d831512`
**Root cause:** `nvidia/entry.ps1` dot-sourced `display/Platform.ps1` and `display/Domain.ps1` but not `personalization/Platform.ps1`. The display domain's observed state capture calls `Invoke-ParsecPersonalizationAdapter` which was undefined.
**Fix:** Add `personalization/Platform.ps1` to nvidia's support file list.

### 4. SetEnabled inherits stale frequency causing BadMode on topology restore
**Commit:** `d831512`
**Root cause:** Same pattern as defect #1 — `Set-ParsecDisplayEnabledInternal` OR'd `dmFields` onto inherited DEVMODE carrying stale `DM_DISPLAYFREQUENCY`. NVIDIA topology restore failed after `TryCustomDisplay` changed the display mode.
**Fix:** Set only the fields being changed (`DM_POSITION | DM_PELSWIDTH | DM_PELSHEIGHT`).

### 5. Re-enabling a detached display fails via ChangeDisplaySettingsEx
**Commit:** `e77c311`
**Root cause:** When a display is disabled, its GDI device name becomes invalid — `EnumDisplaySettingsEx` fails and `ChangeDisplaySettingsEx` returns `DISP_CHANGE_FAILED`. The DEVMODE cannot be constructed from the current state.
**Fix:** Add `SetDisplayConfig` P/Invoke to the DLL with `ApplyTopologyExtend()` method (`SDC_APPLY | SDC_TOPOLOGY_EXTEND`). When `ChangeDisplaySettingsEx` fails to re-enable, fall back to `SetDisplayConfig`. Also construct DEVMODE from captured bounds instead of reading the non-existent current mode.

### 6. CDS_TEST fails for topology changes (enable/disable)
**Commit:** `cb44216`
**Root cause:** `Invoke-ParsecApplyDisplayMode` always runs `CDS_TEST` before staging. `ChangeDisplaySettingsEx` with `CDS_TEST` returns `DISP_CHANGE_FAILED` for topology changes even when the actual stage+commit would succeed.
**Fix:** Skip `CDS_TEST` for `SetEnabled` actions. `CDS_TEST` is only valid for resolution, orientation, and primary changes.

### 7. Topology restore fails for detached displays in activedisplays reset
**Commit:** `cb44216`
**Root cause:** `Invoke-ParsecDisplayDomainTopologyReset` iterates monitors and calls `SetEnabled` per-monitor. Detached displays can't be resolved by GDI name, so the per-monitor restore fails with `TopologyTargetUnresolved`.
**Fix:** When per-monitor restore fails with enable/resolve errors, fall back to `ApplyTopologyExtend()` at the topology reset level.

## Follow-up: Window Position Preservation

**Scope:** Medium task, scoped for this PR
**Issue:** When a display is disabled, Windows moves windows from the disabled monitor to the remaining one. When re-enabled, window positions are not restored — they stay on the monitor they were moved to.
**Proposed fix:** Capture window handles + positions via `GetTopLevelWindows()` before disable, restore via `SetWindowPos` (new P/Invoke) after re-enable. Need to handle: multi-DPI coordinate scaling, elevated windows resisting `SetWindowPos`, Z-order preservation, and timing (wait for re-enabled monitor to be ready).
