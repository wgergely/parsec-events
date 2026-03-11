# Parsec Display Mode Automation — Research Documentation

## Project Goal

Automate the transition between "desktop mode" (multi-monitor, native resolution, landscape, default scaling) and "mobile mode" (single monitor, 2000x3000, portrait, 300% UI scaling, 130% text scaling) in response to Parsec remote desktop connect and disconnect events.

## Research Domains

Each domain addresses an independent technical concern. Together they define the architecture of the automation system.

| # | Domain | Key Question | Status |
|---|---|---|---|
| 01 | [Event Detection](./01-event-detection/research.md) | How do we detect Parsec connect/disconnect? | Viable — log file tailing |
| 02 | [Display Configuration](./02-display-configuration/research.md) | How do we change resolution, orientation, topology? | Viable — CCD API via DisplayConfig module |
| 03 | [DPI and Scaling](./03-dpi-and-scaling/research.md) | How do we change UI scaling and text scaling? | Viable but complex — registry + explorer restart |
| 04 | [Profile System](./04-profile-system/research.md) | How do we save and restore complete display states? | Viable — composite profiles |
| 05 | [System Architecture](./05-system-architecture/research.md) | How does it all fit together as a running system? | Designed — phased implementation plan included |

## Key Architecture Decisions Summary

1. **Event source**: Parsec log file tailing via `Get-Content -Wait -Tail` (proven by [auto-parsec](https://github.com/Borgotto/auto-parsec)).
2. **Display API**: CCD API (`SetDisplayConfig` / `QueryDisplayConfig`) via the [DisplayConfig](https://github.com/MartinGC94/DisplayConfig) PowerShell module. Legacy `ChangeDisplaySettingsEx` avoided.
3. **DPI apply strategy**: Registry write + `explorer.exe` restart. No universal mechanism exists for live DPI updates across all applications.
4. **Profile format**: Composite — CCD state in XML, DPI/text scaling in JSON, stored as a profile directory.
5. **Daemon lifecycle**: Task Scheduler at user logon. Not a Windows service (session 0 isolation problem).
6. **State tracking**: Explicit state file on disk; startup state inferred from Parsec log history.

## Open Questions (Require Empirical Testing)

These questions cannot be answered through documentation alone and must be resolved on the target hardware:

- Exact Parsec log line format and regex patterns for current version.
- Parsec log rotation behavior under sustained use.
- Whether `explorer.exe` restart disrupts an active Parsec session.
- Exact `DpiValue` DWORD for 300% on the specific target monitor.
- Parsec display negotiation timing and interaction with script-applied settings.
- Monitor ID stability across topology changes.

## Implementation Phases

Detailed in [05-system-architecture](./05-system-architecture/research.md):

1. **Validation** — empirical testing of all open questions on target hardware.
2. **Core Infrastructure** — log tailer, profile capture, profile applicator.
3. **Integration** — event routing, state machine, configuration.
4. **Hardening** — error handling, logging, manual override, edge case testing.

## Key External References

| Resource | Role |
|---|---|
| [auto-parsec](https://github.com/Borgotto/auto-parsec) | Reference implementation for Parsec log tailing |
| [DisplayConfig module](https://github.com/MartinGC94/DisplayConfig) | PowerShell CCD API wrapper |
| [MultiMonitorTool](https://www.nirsoft.net/utils/multi_monitor_tool.html) | Fallback display profile save/restore |
| [MonitorSwapAutomation](https://github.com/Nonary/MonitorSwapAutomation) | Architectural reference (similar problem for Sunshine) |
| [parsec-vdd](https://github.com/nomi-san/parsec-vdd) | Parsec virtual display driver (may be relevant for headless scenarios) |
| [Microsoft CCD API docs](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/setdisplayconfig-summary-and-scenarios) | Official API documentation |
