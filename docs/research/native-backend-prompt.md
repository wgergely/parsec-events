You are continuing work on the parsec-events project. The compiled C# native backend (Phase 1/3/5) is complete — all inline `Add-Type -TypeDefinition` C# has been extracted into `ParsecEventExecutor.Native.dll`, live-verified on NVIDIA RTX 4080 Super via Parsec, and shipped in PR #4 on branch `feature/win-api`.

Read these documents before starting any work:

1. `docs/research/native-backend-handover.md` — full status, what was built, what remains, architecture decisions, and live verification results
2. `docs/audit/2026-03-15-ingredient-live-test-audit.md` — ingredient verification status and testing flow
3. `docs/audit/2026-03-14-live-integration-test-audit.md` — previous live test session with defect history

## What Is Done

- `src/ParsecEventExecutor.Native/` — compiled `net9.0-windows` class library (9 source files) containing `DisplayNative`, `PersonalizationNative`, and `NvidiaApiNative` classes
- All ~870 lines of inline C# removed from PowerShell; module loads DLL via `RequiredAssemblies`
- `StepAltTab`/`ActivateWindow` rewritten for Parsec UIPI compatibility (AttachThreadInput instead of SendInput)
- `tools/Build-NativeLibrary.ps1` build script with pre-commit integration
- All 42+ PowerShell call sites unchanged; 106 Pester tests pass
- All APIs live-verified with capture→apply→reset on production hardware

## What Remains

### Priority 1: UISettingsController Text Scale (Phase 2)

The `display.set-textscale` ingredient currently uses registry writes + `WM_SETTINGCHANGE` broadcast which does not trigger the WinRT `TextScaleFactorChanged` event. The proper API is `UISettingsController.SetTextScaleFactor()` from `Windows.UI.ViewManagement.Core`, which requires the `iot:systemManagement` restricted capability declared in an MSIX manifest.

This needs a separate MSIX-packaged CLI executable (`src/ParsecEventExecutor.TextScale/`) that PowerShell calls as a subprocess for text scale set/get operations. The existing class library DLL cannot use this API because restricted capabilities require MSIX packaging. The `Set-ParsecTextScaleStateInternal` function in `personalization/Platform.ps1` would call this CLI instead of doing the registry write + broadcast double-apply workaround.

API references are in the handover doc. Blocked ingredients: `display.set-textscale`, `display.set-uiscale`, `display.set-scaling`.

### Priority 2: Window Management Ingredients (Phase 4)

The DLL already contains compiled and live-verified window management methods (`GetTopLevelWindows`, `GetForegroundWindowCapture`, `StepAltTab`, `ActivateWindow`) that are not yet wired to any ingredient. Create ingredients when use cases are defined.

## Constraints

- PowerShell 7.5+ required (net9.0-windows DLL)
- Build before testing: `pwsh tools/Build-NativeLibrary.ps1`
- Test baseline: `Invoke-Pester -Path tests/` — 106 tests passing
- Branch: `feature/win-api`, PR #4
- System: NVIDIA RTX 4080 Super, Windows 11, ASUS PA278CV via DisplayPort, Parsec virtual display adapter present
