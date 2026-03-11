# System Architecture: Daemon Lifecycle, Orchestration, and Error Handling

## Status: Design Phase — Synthesizes Decisions From All Other Research Domains

## Problem Statement

The individual research domains (event detection, display configuration, DPI scaling, profile system) each solve a piece of the puzzle. This document addresses how they compose into a running system: how the daemon starts, how it manages its lifecycle, how it sequences operations, and how it handles failures.

## Architectural Overview

The system is a long-running PowerShell process that:

1. Starts at user logon (via Task Scheduler).
2. Tails the Parsec log file for connection events.
3. On connect: applies the "mobile" profile.
4. On disconnect: applies the "desktop" profile.
5. Runs indefinitely until the user logs off or explicitly stops it.

### Component Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    Task Scheduler                        │
│              (triggers at user logon)                    │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│                  Watcher (main loop)                     │
│                                                         │
│  ┌───────────────┐    ┌──────────────┐                  │
│  │  Log Tailer   │───▶│ Event Router │                  │
│  │ (Get-Content  │    │ (regex match │                  │
│  │  -Wait -Tail) │    │  + dispatch) │                  │
│  └───────────────┘    └──────┬───────┘                  │
│                              │                          │
│                    ┌─────────┴─────────┐                │
│                    ▼                   ▼                 │
│           ┌──────────────┐   ┌──────────────┐           │
│           │  On Connect  │   │ On Disconnect│           │
│           │  (apply      │   │ (apply       │           │
│           │   mobile)    │   │  desktop)    │           │
│           └──────┬───────┘   └──────┬───────┘           │
│                  │                  │                    │
│                  ▼                  ▼                    │
│           ┌─────────────────────────────────┐           │
│           │      Profile Applicator         │           │
│           │                                 │           │
│           │  1. Set topology (CCD API)      │           │
│           │  2. Set resolution/orientation  │           │
│           │  3. Write DPI registry          │           │
│           │  4. Write text scaling registry │           │
│           │  5. Restart explorer.exe        │           │
│           └─────────────────────────────────┘           │
│                                                         │
│  ┌───────────────────────────────────────────────┐      │
│  │              Profile Store                    │      │
│  │  profiles/desktop/  │  profiles/mobile/       │      │
│  │    display.xml      │    display.xml          │      │
│  │    scaling.json     │    scaling.json         │      │
│  └───────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────┘
```

## Design Decisions

### 1. Daemon Lifecycle: Task Scheduler vs. Windows Service vs. Startup Script

| Option | Pros | Cons |
|---|---|---|
| **Task Scheduler (at logon)** | No admin required for user-level tasks; native restart-on-failure; visible in standard tooling | PowerShell process visible in task manager; no clean stop/start UI |
| **Windows Service** | True background process; service management UI; auto-restart built in | Requires admin to install; services run in session 0 (no desktop interaction by default); complex for PowerShell |
| **Startup folder shortcut** | Simplest possible | No restart-on-failure; no scheduling; no visibility |

**Recommendation**: Task Scheduler with a "At log on" trigger for the specific user. Configure the task with "Restart on failure" (e.g., every 1 minute, up to 3 retries). This provides daemon-like behavior without the session 0 isolation problem that plagues Windows services that need desktop access.

**Critical constraint**: The display configuration APIs must run in the user's desktop session (Session 1+), not in Session 0. A Windows service would require `CreateProcessAsUser` or similar workarounds to interact with the desktop. Task Scheduler runs in the user's session natively.

### 2. State Machine

The watcher operates as a simple two-state machine:

```
              connect event
    ┌──────┐ ───────────────▶ ┌────────┐
    │DESKTOP│                  │ MOBILE │
    └──────┘ ◀─────────────── └────────┘
             disconnect event
```

The current state must be tracked explicitly (not inferred from display settings) to avoid re-applying profiles redundantly. A small state file (e.g., `state.json` containing `{ "mode": "desktop" }`) persisted to disk ensures the correct state survives a watcher restart.

**Edge case**: If the watcher starts while a Parsec session is already active, it should detect this (e.g., by checking the last N lines of the log for an unmatched connect event) and set its initial state accordingly, rather than assuming "desktop."

### 3. Operation Sequencing and Timing

The profile applicator must sequence operations carefully (see `04-profile-system` for ordering rationale). Two timing concerns arise:

**Parsec display negotiation race**: When Parsec connects, it may perform its own display configuration (if the client requests a resolution match). The automation script must not fight Parsec's changes. Options:

- **Option A**: Introduce a configurable delay (e.g., 2–5 seconds) after detecting the connect event before applying the profile. This lets Parsec finish its negotiation first.
- **Option B**: Disable Parsec's auto-resolution-match in Parsec's settings, giving the script full control.
- **Option C**: Use the WMI display change event (see `01-event-detection`) as a secondary trigger — wait for the display to stabilize after Parsec's own changes, then apply the profile.

**Recommendation**: Option B (disable Parsec's auto-resolution) combined with a small safety delay (Option A). This gives the script deterministic control without relying on race-condition timing.

**Explorer restart timing**: After writing DPI and text scaling to the registry, `explorer.exe` must be restarted. The restart itself takes 2–5 seconds. No subsequent operations should depend on explorer being running.

### 4. Error Handling Strategy

Each operation in the profile applicator can fail independently. The strategy:

1. **Topology change failure** (e.g., expected monitor not connected): Abort the entire profile apply. Log the error. Remain in the current state. Do not proceed to DPI/scaling changes for a topology that didn't materialize.

2. **Resolution/orientation failure** (e.g., unsupported mode): Log the error. Attempt to continue with remaining settings (DPI, text scaling) since they may still be useful even at the wrong resolution.

3. **Registry write failure** (e.g., permissions): Log the error. This should not happen under normal conditions since the user's HKCU hive is writable without elevation. If it does, it indicates a deeper system problem.

4. **Explorer restart failure**: If `Stop-Process -Name explorer` fails, log and continue. Explorer may not be running (e.g., if it crashed earlier). The new explorer instance will start automatically or can be started explicitly.

**Global principle**: Never leave the system in an unknown state. If a profile apply fails partway through, the state file should reflect the *actual* applied state (which may be neither "desktop" nor "mobile" but a partial hybrid). The next event should trigger a full re-apply from scratch rather than a delta.

### 5. Logging and Observability

The daemon should maintain its own log file (separate from Parsec's) recording:

- Startup and shutdown events.
- Each detected Parsec event (connect/disconnect) with timestamp.
- Each profile apply attempt with per-step success/failure.
- Any errors with full context.

Log rotation should be implemented (e.g., keep last 7 days or last 1 MB) to prevent unbounded growth.

### 6. Configuration

A single configuration file (JSON or TOML) controls runtime behavior:

| Setting | Purpose | Default |
|---|---|---|
| `parsec_log_path` | Path to Parsec's log.txt | Auto-detect based on install type |
| `profiles_dir` | Directory containing profile definitions | `./profiles/` |
| `apply_delay_ms` | Delay after event detection before applying profile | 3000 |
| `restart_explorer` | Whether to restart explorer.exe after DPI changes | true |
| `log_path` | Path to the daemon's own log file | `./daemon.log` |
| `log_level` | Verbosity: debug, info, warn, error | info |

### 7. Manual Override

The system should support manual profile switching independent of Parsec events. This serves two purposes:

- Initial profile capture during setup.
- Emergency recovery if the automation gets stuck.

This is a simple CLI interface: `.\switch-profile.ps1 -Profile desktop` or `.\switch-profile.ps1 -Profile mobile`.

### 8. Upgrade and Maintenance Path

Parsec updates may change the log format. The regex patterns used for event detection should be isolated in configuration (not hardcoded) so they can be updated without modifying the script logic. The auto-parsec project's modular approach is a good model here.

## Phased Implementation Plan

### Phase 1: Validation (empirical testing)
- Capture actual Parsec log entries from a live connect/disconnect cycle.
- Validate CCD API display switching on the target hardware.
- Validate DPI registry changes + explorer restart behavior during a Parsec session.
- Determine exact DpiValue encoding for 300% on the target monitor.

### Phase 2: Core Infrastructure
- Build the log tailer and event router.
- Build the profile capture tool (save current state to profile directory).
- Build the profile applicator (apply a profile from directory).

### Phase 3: Integration
- Wire the event router to the profile applicator.
- Add state tracking (state file, startup state detection).
- Add the configuration file.
- Create the Task Scheduler entry.

### Phase 4: Hardening
- Add error handling and logging.
- Add manual override CLI.
- Test edge cases: multiple clients, rapid connect/disconnect, hardware changes.
- Document the setup procedure.

## References

- [auto-parsec — modular PowerShell architecture for Parsec automation](https://github.com/Borgotto/auto-parsec)
- [MonitorSwapAutomation — similar architecture for Sunshine/Moonlight](https://github.com/Nonary/MonitorSwapAutomation)
- [parsec-vdd — Parsec virtual display driver](https://github.com/nomi-san/parsec-vdd)
- [auto-parsec-vdd — automatic Parsec VDD management](https://github.com/michyprima/auto-parsec-vdd)
- [vddswitcher — Parsec VDD switching tool](https://github.com/VergilGao/vddswitcher)
- [DisplayConfig PowerShell module](https://github.com/MartinGC94/DisplayConfig)
- [Microsoft: Task Scheduler documentation](https://learn.microsoft.com/en-us/windows/win32/taskschd/task-scheduler-start-page)
- [Microsoft: SetDisplayConfig — session requirements](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setdisplayconfig)
