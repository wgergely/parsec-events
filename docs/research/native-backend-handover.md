# Native C# Backend — Handover Document

## Problem Statement

The PowerShell ingredient framework contains ~1000 lines of inline C# embedded as string literals in `Add-Type -TypeDefinition` blocks. This code has no compile-time checking, no IDE support, and no independent tests. Additionally, the `display.set-textscale` ingredient cannot reliably trigger UI re-renders because the proper Windows API (`UISettingsController.SetTextScaleFactor`) requires a restricted capability only available to packaged (MSIX) apps.

## Research Findings

### Text Scale API

The official API for setting text scale is `Windows.UI.ViewManagement.Core.UISettingsController`:
- **Class:** `UISettingsController` in `Windows.UI.ViewManagement.Core`
- **Method:** `SetTextScaleFactor(double value)` where value is 1.0–2.25 (representing 100%–225%)
- **Availability:** Windows 10 version 2004+ (10.0.19041.0), UniversalApiContract v10.0
- **Obtain instance:** `UISettingsController.RequestDefaultAsync()`
- **Restricted capability required:** `iot:systemManagement` in the app manifest

The Windows Settings app (`SystemSettings.exe`) is a packaged UWP app that uses this API internally. It fires the full WinRT notification chain including `UISettings.TextScaleFactorChanged`, which is what UWP/WinUI apps listen for. Direct registry writes (`HKCU:\SOFTWARE\Microsoft\Accessibility\TextScaleFactor`) + `WM_SETTINGCHANGE` broadcast do NOT trigger the WinRT event.

**References:**
- [UISettingsController Class](https://learn.microsoft.com/en-us/uwp/api/windows.ui.viewmanagement.core.uisettingscontroller?view=winrt-26100)
- [UISettingsController.SetTextScaleFactor](https://learn.microsoft.com/en-us/uwp/api/windows.ui.viewmanagement.core.uisettingscontroller.settextscalefactor?view=winrt-22621)
- [UISettings.TextScaleFactor (read-only)](https://learn.microsoft.com/en-us/uwp/api/windows.ui.viewmanagement.uisettings.textscalefactor?view=winrt-22621)
- [Raymond Chen: reading text scale factor](https://devblogs.microsoft.com/oldnewthing/20230830-00/?p=108680)
- [App capability declarations](https://learn.microsoft.com/en-us/windows/uwp/packaging/app-capability-declarations)

### Current Inline C# Inventory

| Location | Lines | Purpose |
|----------|-------|---------|
| `Domains/display/Platform.ps1` | ~500 | Display configuration (CCD), resolution, orientation, DPI, window enumeration, SendInput, virtual desktop COM |
| `Domains/personalization/Platform.ps1` | ~30 | `SendMessageTimeout` for `WM_SETTINGCHANGE` broadcast |
| `NvidiaInterop.ps1` | ~340 | NVAPI P/Invoke (nvapi64.dll dynamic loading, custom resolution management) |

### APIs That Should Migrate

| API | Current Approach | C# Backend Approach |
|-----|-----------------|---------------------|
| Text scale set | Registry + broadcast (unreliable) | `UISettingsController.SetTextScaleFactor()` |
| Display config | Inline C# `Add-Type` | Compiled assembly with type safety |
| NVIDIA interop | Inline C# `Add-Type` | Compiled assembly with proper struct marshalling |
| Window enum | Inline C# `Add-Type` | Compiled assembly |
| WM_SETTINGCHANGE | Inline C# `Add-Type` | Compiled assembly |

### APIs Fine to Leave in PowerShell

| API | Reason |
|-----|--------|
| Sound (WMI/CIM) | Pure PowerShell cmdlets |
| Process/Service lifecycle | Native `Start-Process`, `Get-Service` |
| Command invoke | `Start-Process` |
| Theme state | Registry is the documented method; no better API exists |

## Proposed Architecture

### Project: `src/ParsecEventExecutor.Native/`

```
src/ParsecEventExecutor.Native/
├── ParsecEventExecutor.Native.csproj   # net8.0-windows10.0.19041.0
├── Program.cs                          # CLI entry point
├── Display/
│   ├── DisplayNative.cs                # CCD, EnumDisplaySettings, ChangeDisplaySettingsEx
│   ├── MonitorInfo.cs                  # Monitor enumeration, DPI queries
│   └── WindowManager.cs               # Window enum, activation, SendInput
├── Personalization/
│   ├── TextScale.cs                    # UISettingsController.SetTextScaleFactor
│   └── Broadcast.cs                    # WM_SETTINGCHANGE broadcasting
├── Nvidia/
│   └── NvApi.cs                        # NVAPI P/Invoke wrapper
└── Package.appxmanifest                # MSIX manifest with systemManagement capability
```

### CLI Interface

PowerShell calls the compiled binary as a subprocess:

```
ParsecEventExecutor.Native.exe set-text-scale --value 125
ParsecEventExecutor.Native.exe get-text-scale
ParsecEventExecutor.Native.exe set-primary --device \\.\DISPLAY1
ParsecEventExecutor.Native.exe get-displays
```

JSON output on stdout, exit code for success/failure. This keeps the PowerShell ingredient framework as the orchestrator while the C# binary handles all Win32/WinRT interop.

### MSIX Packaging

Required for `UISettingsController` restricted capability:
- `Package.appxmanifest` declares `iot:systemManagement` capability
- Build with `dotnet publish` + MSIX packaging tools
- Self-signed certificate for development, proper signing for distribution
- The binary runs unpackaged for all APIs except text scale; MSIX is only needed for the restricted capability path

### Migration Strategy

1. **Phase 1:** Create the C# project, migrate display interop (`DisplayNative` class) — this is the largest block and already C#
2. **Phase 2:** Add `UISettingsController` text scale support with MSIX packaging
3. **Phase 3:** Migrate NVIDIA interop
4. **Phase 4:** Migrate window management, broadcast
5. **Phase 5:** Remove all `Add-Type -TypeDefinition` blocks from PowerShell, update adapters to call the compiled binary

### PowerShell Integration

The existing adapter pattern (`Invoke-ParsecDisplayAdapter`, `Invoke-ParsecPersonalizationAdapter`) already abstracts the backend. The migration replaces the adapter implementations — ingredient code doesn't change.

## Blocked Ingredients

The following ingredients are blocked on the native backend for full live verification:

- `display.set-textscale` — broadcast-only path doesn't trigger WinRT event
- `display.set-uiscale` — depends on reliable text scale for composite scaling
- `display.set-scaling` — composite ingredient wrapping text + UI scale

## Current PR Status

PR #2 (`feature/shared-state`) delivers the ingredient architecture and is ready to merge. The native backend should be a new PR (`feature/native-backend`) branched from main after merge.

## Session Reference

- Conversation ID: `3acd1e99-972b-4384-9c48-ce2d53daa8fe`
- Audit doc: `docs/audit/2026-03-15-ingredient-live-test-audit.md`
- Previous audit: `docs/audit/2026-03-14-live-integration-test-audit.md`
