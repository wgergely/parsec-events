You are continuing work on the parsec-events project. Your task is to create a compiled C# native backend binary that replaces ~1000 lines of inline C# currently embedded as string literals inside PowerShell `Add-Type -TypeDefinition` blocks, and adds proper Windows API access for text scaling via `UISettingsController.SetTextScaleFactor`.

Read these documents before starting any work:

1. `docs/research/native-backend-handover.md` — full research findings, proposed architecture, migration strategy, and API references
2. `docs/audit/2026-03-15-ingredient-live-test-audit.md` — current ingredient verification status and testing flow
3. `docs/audit/2026-03-14-live-integration-test-audit.md` — previous live test session with defect history
4. `.claude/CLAUDE.md` — project conventions and constraints

The inline C# that needs migrating lives in three files:

- `src/ParsecEventExecutor/Private/Domains/display/Platform.ps1` — ~500 lines: display configuration (CCD QueryDisplayConfig, ChangeDisplaySettingsEx, EnumDisplaySettings), monitor enumeration, DPI queries, window enumeration/activation, SendInput, IVirtualDesktopManager COM, wallpaper via SystemParametersInfo
- `src/ParsecEventExecutor/Private/Domains/personalization/Platform.ps1` — ~30 lines: SendMessageTimeout for WM_SETTINGCHANGE broadcast
- `src/ParsecEventExecutor/Private/NvidiaInterop.ps1` — ~340 lines: NVAPI P/Invoke via nvapi64.dll dynamic loading, custom resolution structs and marshalling

Create a new C# project at `src/ParsecEventExecutor.Native/` targeting `net8.0-windows10.0.19041.0`. The binary should expose a CLI interface that PowerShell calls as a subprocess — JSON output on stdout, structured error on stderr, exit code for success/failure. The existing PowerShell adapter pattern (`Invoke-ParsecDisplayAdapter`, `Invoke-ParsecPersonalizationAdapter`) already abstracts the backend, so ingredient code should not need changes — only the adapter implementations that call into the native binary.

The critical new capability is `UISettingsController.SetTextScaleFactor()` from `Windows.UI.ViewManagement.Core`, which requires the `iot:systemManagement` restricted capability declared in an MSIX manifest. This is the only proper way to set text scaling — the current registry write + WM_SETTINGCHANGE broadcast approach does not trigger the WinRT `TextScaleFactorChanged` event that UWP/WinUI apps listen for. Research and API references are in the handover doc.

Migration phases from the handover doc: (1) display interop, (2) text scale with MSIX, (3) NVIDIA interop, (4) window management and broadcast, (5) remove all Add-Type blocks from PowerShell. Ground each phase in Microsoft developer documentation before implementing. Run `Invoke-Pester -Path tests/` after each phase to verify no regressions — current baseline is 106 tests passing.

Branch from main after PR #2 merges. Target branch name: `feature/native-backend`.
