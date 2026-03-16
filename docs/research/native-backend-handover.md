# Native C# Backend — Handover Document

## Status: Phase 1 Complete (PR #4)

Phases 1, 3, and 5 from the original migration plan are **done**. All inline C# has been extracted into a compiled class library DLL. The remaining work is Phase 2 (UISettingsController text scale via MSIX) and integrating the existing window management methods into ingredients.

## What Was Built

### Compiled Class Library: `src/ParsecEventExecutor.Native/`

A `net9.0-windows` class library replacing ~870 lines of inline `Add-Type -TypeDefinition` C# from three PowerShell files. The DLL is loaded via `RequiredAssemblies` in the module manifest — all 42+ PowerShell call sites are unchanged.

```
src/ParsecEventExecutor.Native/
├── ParsecEventExecutor.Native.csproj     # net9.0-windows, x64
├── Display/
│   ├── DisplayNative.cs                  # CCD, resolution, orientation, DPI, window management, wallpaper
│   ├── MonitorCapture.cs                 # Monitor enumeration data class
│   ├── DisplayPathCapture.cs             # CCD path data class
│   ├── DisplayModeCapture.cs             # Display mode data class
│   ├── WindowCapture.cs                  # Window enumeration data class
│   └── IVirtualDesktopManager.cs         # COM interface for virtual desktop queries
├── Personalization/
│   └── PersonalizationNative.cs          # WM_SETTINGCHANGE broadcast via SendMessageTimeout
└── Nvidia/
    ├── NvidiaApiNative.cs                # NVAPI dynamic loading, custom resolution management
    └── NvidiaCustomDisplayRecord.cs      # Custom resolution data class
```

### Build Tooling

- `tools/Build-NativeLibrary.ps1` — builds the project and copies DLL to the module directory
- Pre-commit hook (`tools/Invoke-PreCommitChecks.ps1`) — rebuilds DLL before every commit
- `.gitignore` excludes built DLL and build artifacts — always build from source

### PowerShell Changes

The three `Initialize-*Interop` functions that contained `Add-Type -TypeDefinition` blocks are now guard-only functions that throw if the DLL type isn't loaded:

- `display/Platform.ps1` — removed ~1180 lines of inline C# (DisplayNative class)
- `personalization/Platform.ps1` — removed ~30 lines of inline C# (PersonalizationNative class)
- `NvidiaInterop.ps1` — removed ~330 lines of inline C# (NvidiaApiNative class)

Module manifest (`ParsecEventExecutor.psd1`) updated:
- `RequiredAssemblies = @('ParsecEventExecutor.Native.dll')`
- `PowerShellVersion = '7.5'` (requires .NET 9 runtime)

### Parsec Compatibility Fix

`StepAltTab` and `ActivateWindow` were rewritten to work under Parsec remote sessions:
- Old: `SendInput` to synthesize Alt+Tab keystrokes — blocked by UIPI in remote sessions
- New: Window enumeration + `AttachThreadInput` + `SetForegroundWindow` — works under Parsec
- `StepAltTab` now respects virtual desktops and `WS_EX_APPWINDOW` style
- `ActivateWindow` now honors `restoreIfMinimized` parameter via `ShowWindow(SW_RESTORE)`

## Live Verification Results

All APIs verified on NVIDIA RTX 4080 Super, Windows 11, ASUS PA278CV monitor, connected via Parsec.

### Read-only APIs — all pass
- DisplayNative: GetCurrentMonitors, GetDisplayModes (111 modes), GetDeviceMode (3000x2000@60Hz), GetDpiScaleForDevice (175%), GetPrimaryDpiScale, GetDesktopWallpaperPath, CreatePositionOnlyDevMode, GetDisplayConfigPaths (288 paths), GetForegroundWindowCapture, GetTopLevelWindows
- PersonalizationNative: BroadcastSettingChange (6 area variants)
- NvidiaApiNative: EnsureInitialized, GetDisplayIdByDisplayName, EnumCustomDisplays (6 custom resolutions)

### Mutating APIs — all pass with capture/apply/reset
- Resolution: 3000x2000 → 1920x1080 → 3000x2000
- Orientation: Landscape → Portrait → Landscape
- UI Scale/DPI: 175% → 150% → 175%
- Wallpaper: original → empty → original
- Window activation: ActivateWindow works, StepAltTab works
- NVIDIA: TryAndSaveCustomDisplay added 1600x900@60Hz (no delete API — by design)

### Known Limitation
- `StepAltTab` cycles between windows using Z-order enumeration, not the OS MRU list. Some windows (e.g., Parsec's framerate window) can interfere with focus. Not a blocker — `ActivateWindow` with a specific handle is reliable.

## Remaining Work

### Phase 2: UISettingsController Text Scale (NEW CAPABILITY)

The `display.set-textscale` ingredient currently uses registry writes + `WM_SETTINGCHANGE` broadcast, which does not trigger the WinRT `TextScaleFactorChanged` event that UWP/WinUI apps listen for. The proper API is `UISettingsController.SetTextScaleFactor()`.

**Requirements:**
- `UISettingsController` class in `Windows.UI.ViewManagement.Core`
- Method: `SetTextScaleFactor(double value)` where value is 1.0–2.25 (100%–225%)
- Obtain instance: `UISettingsController.RequestDefaultAsync()`
- **Restricted capability:** `iot:systemManagement` in an MSIX manifest
- Availability: Windows 10 version 2004+ (10.0.19041.0), UniversalApiContract v10.0

**Architecture decision:** This requires MSIX packaging, which the class library DLL cannot provide. Build a separate small CLI executable (`src/ParsecEventExecutor.TextScale/`) that PowerShell calls as a subprocess for text scale operations only. All other APIs stay in the class library.

**References:**
- [UISettingsController Class](https://learn.microsoft.com/en-us/uwp/api/windows.ui.viewmanagement.core.uisettingscontroller?view=winrt-26100)
- [UISettingsController.SetTextScaleFactor](https://learn.microsoft.com/en-us/uwp/api/windows.ui.viewmanagement.core.uisettingscontroller.settextscalefactor?view=winrt-22621)
- [UISettings.TextScaleFactor (read-only)](https://learn.microsoft.com/en-us/uwp/api/windows.ui.viewmanagement.uisettings.textscalefactor?view=winrt-22621)
- [Raymond Chen: reading text scale factor](https://devblogs.microsoft.com/oldnewthing/20230830-00/?p=108680)
- [App capability declarations](https://learn.microsoft.com/en-us/windows/uwp/packaging/app-capability-declarations)

**Blocked ingredients:**
- `display.set-textscale` — broadcast-only path doesn't trigger WinRT event
- `display.set-uiscale` — depends on reliable text scale for composite scaling
- `display.set-scaling` — composite ingredient wrapping text + UI scale

### Window Management Ingredients (Phase 4 from original plan)

The DLL already contains compiled window management methods that are not yet wired to any ingredient:

| Method | Purpose | Status |
|--------|---------|--------|
| `GetTopLevelWindows()` | Enumerate all windows with process/title/style info | Compiled, live-verified |
| `GetForegroundWindowCapture()` | Capture foreground window details | Compiled, live-verified |
| `StepAltTab()` | Cycle to next alt-tab-eligible window | Compiled, live-verified, Parsec-compatible |
| `ActivateWindow(handle, restore)` | Activate a specific window by handle | Compiled, live-verified |

These are ready to be wired into ingredients when the use case is defined (e.g., a `window.activate` or `window.focus` ingredient).

## Migration Phase Summary

| Phase | Scope | Status |
|-------|-------|--------|
| 1 | Display interop (DisplayNative) | **Done** — PR #4 |
| 2 | UISettingsController text scale with MSIX | **Not started** |
| 3 | NVIDIA interop (NvidiaApiNative) | **Done** — PR #4 |
| 4 | Window management ingredients | **DLL ready**, ingredients not yet created |
| 5 | Remove all Add-Type blocks | **Done** — PR #4 |

## Dev Environment

- .NET SDK 9.0.312 (already installed, no additional setup needed)
- PowerShell 7.5.4 on .NET 9.0.10
- Build: `pwsh tools/Build-NativeLibrary.ps1`
- Test: `Invoke-Pester -Path tests/` (106 tests, all pass)

## PR History

- PR #2 (`feature/shared-state`) — ingredient architecture (merged)
- PR #4 (`feature/win-api`) — compiled C# native backend (this work)
