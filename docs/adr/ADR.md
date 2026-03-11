# Architecture Decision Record: Parsec Display Mode Automation

**Date**: 2026-03-11
**Status**: Accepted
**Author**: Gergely Wootsch

---

## Context

A workstation with two or three monitors runs in a standard desktop configuration for in-person use. The same machine is accessed remotely via Parsec from a mobile device, which requires a radically different display configuration: a single 2000x3000 portrait monitor at 300% UI scaling and 130% text scaling. Today, switching between these modes is a manual process involving multiple Settings panels, registry changes, and window rearrangement. The goal is to fully automate this transition, triggered by Parsec connect and disconnect events.

Five research domains were investigated. This ADR records the binding decisions for each, the rationale behind them, and the known risks that must be validated empirically before implementation begins.

---

## ADR-1: Event Detection

### Decision

Use Parsec's local log file as the primary event source, monitored via PowerShell's `Get-Content -Wait -Tail`.

### Options Considered

| Option | Verdict | Reason |
|---|---|---|
| Parsec log file tailing | **Chosen** | Proven by community tooling; no privileges required; graceful degradation |
| Windows Event Log | Rejected | Parsec does not register an Event Log provider; no usable Event IDs |
| WMI display change events | Deferred as supplementary | Detects consequences, not causes; too imprecise as a primary trigger |
| WM_DISPLAYCHANGE message pump | Deferred as supplementary | Same imprecision as WMI; requires a compiled listener |
| Process tree monitoring | Rejected | Undocumented, version-fragile, no community precedent |
| Parsec Audit API | Rejected | Enterprise-only; requires API access not available on personal plans |

### Log File Locations

| Install Type | Path |
|---|---|
| Per-user | `%APPDATA%\Parsec\log.txt` |
| Per-machine | `%ProgramData%\Parsec\log.txt` |

### Consequences

The watcher depends on Parsec's log format, which is undocumented and may change between versions. Regex patterns should be externalized to configuration so they can be updated without code changes. The system degrades safely: a format change causes the watcher to stop matching events (no action taken), rather than applying profiles incorrectly.

### Validation Required

- Capture exact log line patterns from a live Parsec connect/disconnect cycle on the target machine.
- Confirm log rotation/truncation behavior under sustained use.
- Confirm sub-second latency between the actual event and the log entry appearing.

### Reference Implementation

[auto-parsec](https://github.com/Borgotto/auto-parsec) — modular PowerShell framework using this exact approach with pluggable action scripts.

---

## ADR-2: Display Configuration API

### Decision

Use the CCD (Connecting and Configuring Displays) API via the [DisplayConfig](https://github.com/MartinGC94/DisplayConfig) PowerShell module. Keep [MultiMonitorTool](https://www.nirsoft.net/utils/multi_monitor_tool.html) as a fallback for profile save/restore.

### Options Considered

| Option | Verdict | Reason |
|---|---|---|
| CCD API via DisplayConfig module | **Chosen** | Modern, supported API; separates source/target modes; atomic multi-display apply; PowerShell-native |
| Legacy ChangeDisplaySettingsEx | Rejected | Deprecated by Microsoft; conflates source and target modes; per-display commit dance; driver rotation support inconsistent |
| MultiMonitorTool (NirSoft) | Retained as fallback | Simple save/load workflow; useful if DisplayConfig module has gaps; external binary dependency |
| Direct P/Invoke of CCD API | Rejected | Reinvents what DisplayConfig already provides; high maintenance burden |

### Key Capabilities Required

The API must support, and the CCD API via DisplayConfig provides:

- Enabling/disabling individual monitors (topology change from extend to single).
- Setting resolution per monitor, including non-standard resolutions like 2000x3000.
- Setting orientation per monitor (landscape ↔ portrait).
- Designating the primary monitor.
- Querying current state for profile capture.
- Exporting/importing full configuration for profile persistence (via `Export-Clixml`).
- Atomic multi-setting apply to minimize display flicker.

### Consequences

The project takes a dependency on the DisplayConfig PowerShell module (MIT licensed, single maintainer, 164 stars, 97.5% C#). If the module becomes unmaintained, the fallback path is either MultiMonitorTool or direct CCD P/Invoke. The CCD API itself is stable Windows infrastructure and will not be deprecated.

### Interaction With Parsec

Parsec has a built-in option to match the client's resolution on connect. This feature must be **disabled** in Parsec's configuration to avoid racing with the automation script. The script assumes full control over display configuration.

### Validation Required

- Confirm the DisplayConfig module installs and functions on the target machine's PowerShell version.
- Confirm programmatic portrait rotation works with the specific GPU and driver.
- Confirm monitor identity stability across topology transitions (IDs must be predictable for profile restore).
- Measure display blanking duration during topology change.

---

## ADR-3: DPI and Text Scaling Strategy

### Decision

Apply DPI scaling via `DisplayConfigSetDeviceInfo` with undocumented type parameter `-4`, which is the same mechanism the Windows Settings UI uses. This applies scaling changes immediately with full system-wide effect — no explorer restart, no logoff. Text scaling is applied via registry write plus `WM_SETTINGCHANGE` broadcast.

### Background: The Two DPI Paths

Initial research suggested that programmatic DPI changes required registry writes followed by an `explorer.exe` restart. This was incorrect. The Windows Settings app (and the Display settings panel) uses `DisplayConfigSetDeviceInfo` — part of the same CCD API family used for display topology — with an **undocumented negative type value** in `DISPLAYCONFIG_DEVICE_INFO_HEADER`:

- **Type `-3`**: Get current DPI scaling info for a display.
- **Type `-4`**: Set DPI scaling for a display (immediate apply).

These type values are deliberately omitted from the public `DISPLAYCONFIG_DEVICE_INFO_TYPE` enum (which only documents non-negative values), but they are the actual mechanism the OS uses. A [reverse-engineering study](https://github.com/lihas/windows-DPI-scaling-sample) using WinDbg and Ghidra on `user32.dll` and the immersive control panel confirmed this, and demonstrated that calling `DisplayConfigSetDeviceInfo` with a 24-byte payload containing type `-4` applies scaling changes instantly — identical to the UI behavior.

This is a significant architectural simplification: **DPI scaling uses the same CCD API as display configuration**, removing the need for registry manipulation and shell restarts for this setting.

### Options Considered for Applying DPI Changes

| Option | Verdict | Reason |
|---|---|---|
| `DisplayConfigSetDeviceInfo` (type -4) | **Chosen** | Same mechanism as Settings UI; immediate apply; no restart; part of CCD API family already in use |
| Registry write + explorer restart | Rejected (revised) | Crude workaround; unnecessary given the CCD path; explorer restart disruptive |
| Registry write + full logoff/logon | Rejected | Destroys the Parsec session |
| SPI_SETLOGICALDPIOVERRIDE | Rejected | Different undocumented API; less reliable than the CCD path |
| No DPI change (resolution-only) | Rejected | 2000x3000 at 100% scaling is unusable on a mobile device |

### DPI Scaling Values and Resolution Constraints

Windows calculates the *available* scaling percentages based on the monitor's resolution. The available presets (100%, 125%, 150%, 175%, 200%, 225%, 250%, 300%, 350%, etc.) are constrained such that the effective resolution at the chosen scale remains usable. Windows supports custom scaling up to 500%.

For a 2000x3000 display at 300% scaling, the effective resolution would be approximately 667x1000 logical pixels. This is within the range Windows permits, as the minimum effective dimension Windows enforces is around 480–500 pixels.

**Open question**: Whether 300% appears as a preset option at 2000x3000 depends on Windows' internal heuristics. If it does not, a nearby value (250% or 200%) would need to be used instead, or the target resolution could be adjusted. The `DisplayConfigGetDeviceInfo` call with type `-3` returns the available scaling steps for the active display, which makes this programmatically queryable.

### Text Scaling (Separate Mechanism)

Text scaling (the Accessibility > Text size slider) remains a registry-based setting:

| Setting | Path | Value |
|---|---|---|
| Text scaling | `HKCU\SOFTWARE\Microsoft\Accessibility\TextScaleFactor` | DWORD (100–225, direct percentage) |

After writing to the registry, broadcasting `WM_SETTINGCHANGE` via `SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, ...)` notifies applications. UWP and modern apps respond immediately. Some Win32 apps may not respond until restarted, but this is a minor concern — the primary scaling is handled by the DPI mechanism, and text scaling is a secondary refinement.

### Consequences

This decision **removes the explorer restart from the critical path entirely**. DPI changes apply instantly via the CCD API, just as they do when changed through Settings. The transition sequence becomes cleaner and less disruptive. The Parsec session is unaffected because no shell restart occurs.

The tradeoff is dependence on an undocumented API parameter. However, this parameter has been stable since Windows 8.1 and is the mechanism the OS's own Settings app uses — Microsoft cannot change it without breaking their own UI. The [windows-DPI-scaling-sample](https://github.com/lihas/windows-DPI-scaling-sample) project provides a reference C++ implementation, and the approach can be wrapped via P/Invoke or integrated into the DisplayConfig PowerShell module.

### Validation Required

- Confirm that `DisplayConfigSetDeviceInfo` with type `-4` works on the target machine's Windows build.
- Query available scaling steps via type `-3` at 2000x3000 resolution — confirm 300% is available.
- If 300% is not available at 2000x3000, determine the maximum available scaling and whether an adjusted resolution (e.g., 1500x2250) yields 300% as a preset.
- Confirm text scaling broadcast (`WM_SETTINGCHANGE`) propagates to the apps used during remote sessions.

---

## ADR-4: Profile System

### Decision

Use a composite profile system: CCD API state serialized via the DisplayConfig module (`Export-Clixml`), combined with a JSON sidecar file containing DPI and text scaling values. Profiles are stored as named directories.

### Why Composite

No single tool or API captures the full display state. The CCD API handles topology, resolution, orientation, position, refresh rate, and primary monitor designation — but knows nothing about OS-level DPI scaling or accessibility text scaling, which live in the registry. The profile system must bridge both worlds.

### Profile Structure

```
profiles/
├── desktop/
│   ├── display.xml        # CCD state via DisplayConfig Export-Clixml
│   └── scaling.json       # { "dpi": { "<MonitorID>": <DpiValue> }, "textScale": 100 }
└── mobile/
    ├── display.xml
    └── scaling.json
```

### Capture Workflow

Profiles are captured once during initial setup:

1. Arrange the desktop into the desired multi-monitor layout → run capture → "desktop" profile saved.
2. Manually configure mobile mode → run capture → "mobile" profile saved.

Re-capture is only needed when physical hardware changes.

### Apply Ordering (Strict Sequence)

| Step | Operation | API | Failure Behavior |
|---|---|---|---|
| 1 | Set monitor topology | CCD API (`SetDisplayConfig`) | **Abort all** — downstream steps depend on correct topology |
| 2 | Set resolution and orientation | CCD API (`SetDisplayConfig`) | Log and continue — DPI changes may still be useful |
| 3 | Set per-monitor DPI scaling | CCD API (`DisplayConfigSetDeviceInfo`, type -4) | Log and continue |
| 4 | Set text scaling | Registry (`TextScaleFactor`) + `WM_SETTINGCHANGE` broadcast | Log and continue |

The critical invariant: if step 1 fails, step 3 must not execute, because it would target monitor IDs that don't exist in the current topology. Note that steps 1–3 all use the CCD API family, which simplifies the dependency surface. Step 4 is the only registry-based operation, and its broadcast notification is best-effort.

### Consequences

Two files per profile is slightly more complex than a single monolithic save, but each component uses its native format: the DisplayConfig module's own serialization for display state (which handles adapter ID remapping), and a simple JSON file for registry values (which is human-readable and trivially editable).

### Validation Required

- Confirm `Export-Clixml` → `Import-Clixml` round-trip fidelity for a multi-monitor layout.
- Confirm monitor IDs in `PerMonitorSettings` are predictable after a topology change.
- Determine whether MultiMonitorTool `/SaveConfig` is needed as backup, or if DisplayConfig alone is sufficient.

---

## ADR-5: Daemon Lifecycle

### Decision

Run the watcher as a PowerShell script launched by Task Scheduler at user logon, with restart-on-failure configured.

### Options Considered

| Option | Verdict | Reason |
|---|---|---|
| Task Scheduler (at logon) | **Chosen** | Runs in user session (Session 1+); no admin required; built-in restart-on-failure; standard tooling |
| Windows Service | Rejected | Services run in Session 0 — cannot interact with the desktop or call display APIs without `CreateProcessAsUser` workarounds |
| Startup folder shortcut | Rejected | No restart-on-failure; no scheduling; poor visibility |

### Session Constraint

The display configuration APIs (`SetDisplayConfig`, registry writes to HKCU, `Stop-Process explorer`) all require execution in the user's interactive desktop session. Windows services run in Session 0, which is isolated from the desktop. Task Scheduler tasks triggered at logon run in the user's session natively, satisfying this constraint without workarounds.

### State Persistence

A `state.json` file tracks the current mode (`desktop` or `mobile`). On startup, the watcher reads the last N lines of the Parsec log to determine if a session is already active, and reconciles with the persisted state. This handles the case where the watcher restarts mid-session.

### Consequences

The PowerShell process is visible in Task Manager. There is no service-style stop/start UI — the user must interact with Task Scheduler or kill the process manually. A manual override CLI (`switch-profile.ps1 -Profile desktop`) provides an escape hatch.

---

## ADR-6: Parsec Configuration Prerequisite

### Decision

Disable Parsec's built-in auto-resolution-matching feature. The automation script assumes exclusive control over display configuration.

### Rationale

If Parsec auto-matches the connecting client's resolution, it will apply its own display changes before the script runs. The script would then overwrite Parsec's changes, causing a double-transition (Parsec's resolution → script's resolution) with unnecessary display flicker and potential race conditions.

By disabling Parsec's auto-resolution, the display state remains unchanged on connect. The script detects the connect event via the log, waits a brief configurable delay, and applies the mobile profile as a single clean transition.

### Consequences

The Parsec client will initially see the desktop-mode display (multi-monitor, landscape). After the script's apply delay (default 3 seconds), the display transitions to mobile mode. The client adapts to the new resolution. This brief initial mismatch is the tradeoff for deterministic, single-owner control.

---

## ADR-7: Configuration and Extensibility

### Decision

Use a single JSON configuration file for all runtime parameters. Regex patterns for log parsing are configuration, not code.

### Configuration Surface

| Key | Type | Default | Purpose |
|---|---|---|---|
| `parsec_log_path` | string | Auto-detected | Path to Parsec's `log.txt` |
| `profiles_dir` | string | `./profiles/` | Root directory for profile storage |
| `apply_delay_ms` | integer | 3000 | Delay after event detection before applying profile |
| `broadcast_text_scale` | boolean | true | Whether to broadcast WM_SETTINGCHANGE after text scaling change |
| `log_path` | string | `./daemon.log` | Daemon's own log file |
| `log_level` | string | `info` | Verbosity: debug, info, warn, error |
| `patterns.connect` | string | (regex) | Regex matching a Parsec connect log line |
| `patterns.disconnect` | string | (regex) | Regex matching a Parsec disconnect log line |

### Rationale

Parsec updates may change log line formats. Externalizing the regex patterns means the user can update them without modifying script logic. The auto-parsec project's modular architecture validates this approach.

---

## Consolidated Risk Register

| Risk | Severity | Mitigation | Validation Phase |
|---|---|---|---|
| 300% scaling not available at 2000x3000 resolution | **High** | Query available steps via `DisplayConfigGetDeviceInfo` (type -3); adjust resolution or accept nearest scaling | Phase 1 |
| `DisplayConfigSetDeviceInfo` type -4 unavailable or broken on target Windows build | **High** | Test on target; fallback to registry write + explorer restart if CCD path fails | Phase 1 |
| Parsec log format changes between versions | **Medium** | Externalized regex patterns; graceful no-op on mismatch | Ongoing |
| Monitor IDs are unstable across topology changes | **Medium** | DisplayConfig module handles adapter ID remapping; test with hardware | Phase 1 |
| DisplayConfig module becomes unmaintained | **Low** | MultiMonitorTool as fallback; CCD API is stable Windows infrastructure | Ongoing |
| Rapid connect/disconnect causes profile thrashing | **Low** | Debounce via `apply_delay_ms`; state machine prevents redundant applies | Phase 4 |
| Multiple simultaneous Parsec clients | **Low** | Treat any connect as "go mobile", last disconnect as "go desktop" | Phase 4 |

---

## Implementation Phases

### Phase 1: Empirical Validation

Resolve all items in the risk register marked "Phase 1." No code is written — only manual testing and observation. Deliverables:

- Parsec log line samples with exact patterns for connect/disconnect.
- Confirmed `DisplayConfigSetDeviceInfo` type `-4` functions on target Windows build.
- Query available scaling steps at 2000x3000 via `DisplayConfigGetDeviceInfo` type `-3` — confirm 300% is present.
- If 300% is absent, determine maximum scaling at 2000x3000 and test alternative resolutions (e.g., 1500x2250, 1800x2700) for 300% availability.
- Confirmed DisplayConfig PowerShell module functionality on target PowerShell version.
- Confirmed monitor ID behavior across topology changes.

### Phase 2: Core Components

Build each subsystem independently, testable in isolation:

- Log tailer and event router (input: log file path + regex; output: event callbacks).
- Profile capture tool (input: live system state; output: profile directory).
- Profile applicator (input: profile directory; output: applied display state).

### Phase 3: Integration

Wire the components into the daemon:

- State machine with disk-persisted state.
- Configuration file loading.
- Task Scheduler registration.
- Startup state reconciliation from Parsec log history.

### Phase 4: Hardening

Production-readiness:

- Structured logging with rotation.
- Error handling per the failure hierarchy in ADR-4.
- Manual override CLI.
- Edge case testing (rapid toggling, hardware changes, multi-client).
- Setup documentation.

---

## Key External References

| Resource | Relevance |
|---|---|
| [auto-parsec](https://github.com/Borgotto/auto-parsec) | Reference for Parsec log tailing architecture |
| [DisplayConfig module](https://github.com/MartinGC94/DisplayConfig) | Primary display configuration dependency |
| [MultiMonitorTool](https://www.nirsoft.net/utils/multi_monitor_tool.html) | Fallback display profile tool |
| [MonitorSwapAutomation](https://github.com/Nonary/MonitorSwapAutomation) | Architectural peer for Sunshine/Moonlight |
| [Microsoft: SetDisplayConfig](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setdisplayconfig) | Official CCD API documentation |
| [Microsoft: SetDisplayConfig Scenarios](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/setdisplayconfig-summary-and-scenarios) | CCD topology and mode scenarios |
| [Microsoft: ChangeDisplaySettingsEx](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-changedisplaysettingsexa) | Legacy API (rejected, for reference) |
| [windows-DPI-scaling-sample](https://github.com/lihas/windows-DPI-scaling-sample) | Reference C++ implementation for `DisplayConfigSetDeviceInfo` DPI scaling (type -3/-4) |
| [Microsoft: DPI-related APIs and registry](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dpi-related-apis-and-registry-settings) | DPI scaling mechanisms (official, incomplete — does not document type -3/-4) |
| [Microsoft: Task Scheduler](https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page) | Daemon lifecycle host |
| [Parsec Advanced Configuration](https://support.parsec.app/hc/en-us/articles/360001562772-All-Advanced-Configuration-Options) | Parsec settings surface |
