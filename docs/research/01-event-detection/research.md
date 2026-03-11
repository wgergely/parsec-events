# Event Detection: Parsec Connection Monitoring

## Status: Viable — Recommended Approach Identified

## Problem Statement

When a Parsec client connects to or disconnects from the host machine, no first-class Windows event is fired. Parsec does not register a Windows Event Log provider, so Task Scheduler's "On an event" trigger cannot be used directly. A detection mechanism must be identified that reliably signals connect and disconnect transitions.

## Research Findings

### Primary Approach: Parsec Log File Tailing

Parsec writes real-time session information to a local log file. The file location depends on install type:

| Install Type | Log Path |
|---|---|
| Per-user | `%APPDATA%\Parsec\log.txt` |
| Per-machine | `%ProgramData%\Parsec\log.txt` |

The log contains timestamped entries including client connection and disconnection events. The Parsec console UI (Help > Console) displays the same stream, confirming the log is the canonical source of session state.

**Reference implementation**: The [auto-parsec](https://github.com/Borgotto/auto-parsec) project demonstrates this approach using PowerShell's `Get-Content -Wait -Tail` to continuously monitor the log. The project uses a modular architecture with pluggable action scripts triggered by regex-matched log lines. It detects three event classes: connection attempt, successful connection, and disconnection.

### Alternative Approaches Considered

#### Windows Event Log (not viable as primary)

Parsec does not write to the Windows Event Log with a dedicated provider. Some logon-related events (Event ID 4624, 4625) may fire incidentally depending on Parsec's authentication path, but these are unreliable as discriminators — they cannot distinguish a Parsec session from any other logon source without additional heuristics.

#### WMI Display Configuration Events (supplementary)

Windows exposes `Win32_DisplayConfiguration` and `Win32_VideoController` change events via WMI. PowerShell can subscribe to these using `Register-WmiEvent`. These events fire when display topology changes, which Parsec may trigger if it alters the display on connect. However, this detects the *consequence* (display change) rather than the *cause* (Parsec session), making it imprecise — any display hotplug or settings change would also fire.

**Architecture decision**: This could serve as a secondary validation signal (confirming that a display change actually occurred after a Parsec event was detected) rather than a primary trigger.

#### Win32 Message Pump — WM_DISPLAYCHANGE (supplementary)

The `WM_DISPLAYCHANGE` message is broadcast to all top-level windows when resolution, color depth, or monitor count changes. A small background process with a message loop could listen for this. Same limitation as WMI: it detects display changes generically, not Parsec specifically.

#### Process Monitoring (fragile)

Monitoring the Parsec process tree for child processes or state changes is possible but undocumented and version-dependent. Not recommended.

### Parsec Audit Log API (enterprise only)

Parsec Teams/Enterprise exposes connection events via a downloadable audit log (JSON format, 7-day retention, max 5000 events). The Enterprise tier additionally offers API access. This is not viable for a personal/individual setup but is worth noting for completeness.

**Reference**: [Parsec Team Audit Logs documentation](https://support.parsec.app/hc/en-us/articles/32381584005268-Team-Audit-Logs)

## Open Questions Requiring Empirical Validation

1. **Exact log line format**: The precise regex patterns for connect/disconnect entries need to be captured from a live Parsec session. The auto-parsec project provides starting patterns, but these should be validated against the current Parsec version.

2. **Log rotation behavior**: Does Parsec rotate, truncate, or append indefinitely to `log.txt`? A long-running watcher needs to handle file rotation gracefully (e.g., by detecting file size resets or inode changes).

3. **Latency**: How quickly do log entries appear after the actual connect/disconnect event? Sub-second latency is expected but should be confirmed.

4. **Multiple simultaneous clients**: Does the log clearly distinguish between different client sessions? If two clients connect, does disconnecting one produce an unambiguous entry?

## Architecture Decision Required

**Decision**: Use Parsec log file tailing as the primary event source, with optional WMI display change subscription as a confirmation/validation layer.

**Rationale**: Log tailing is proven by existing community tooling, requires no elevated privileges, no API keys, and no Parsec version-specific hacks. It degrades gracefully (if the log format changes, the watcher simply stops matching, rather than causing harmful side effects).

## References

- [auto-parsec — PowerShell Parsec automation framework](https://github.com/Borgotto/auto-parsec)
- [Parsec Stream Overlay, Stats, and Logging](https://support.parsec.app/hc/en-us/articles/32381603663636-Stream-Overlay-Stats-and-Logging)
- [Parsec App for Windows — install paths and data locations](https://support.parsec.app/hc/en-us/articles/32381199341716-Parsec-App-for-Windows)
- [Parsec Advanced Configuration Options](https://support.parsec.app/hc/en-us/articles/360001562772-All-Advanced-Configuration-Options)
- [MonitorSwapAutomation — related project for Sunshine/Moonlight](https://github.com/Nonary/MonitorSwapAutomation) (architectural reference for similar problem domain)
