# Implementation Plan: Parsec State Watcher — Log Tailing, Event Dispatch, and Per-Device Recipe Binding

**Date**: 2026-03-14
**Status**: Phase 0 Complete — Ready for Implementation (Phase 1+)
**Research**: [`docs/research/07-parsec-state-watcher/research.md`](../research/07-parsec-state-watcher/research.md)
**ADR**: [`docs/adr/2026-03-14-parsec-state-watcher.md`](../adr/2026-03-14-parsec-state-watcher.md)
**Depends on**: Modular ingredient architecture (complete), existing recipe engine (functional)

---

## Scope

This plan covers the full path from "Parsec writes a log line" to "the correct recipe executes automatically, matched to the connecting device." It extends the original two-state (DESKTOP ↔ MOBILE) design to support N device profiles with per-user recipe binding.

### What This Plan Covers

1. Empirical validation of Parsec log format on the target machine
2. Robust log tailing with rotation handling
3. Event routing and user identification
4. Per-user/per-device profile-to-recipe binding via configuration
5. Session tracking (multi-user, grace period, debounce)
6. Watcher lifecycle (Task Scheduler integration)
7. Watcher configuration schema
8. Testing strategy

### What This Plan Does NOT Cover

- New ingredients or domain modules (existing 20 ingredients are sufficient)
- Changes to the recipe engine internals
- Parsec VDD integration (future ingredient, separate plan)
- Interactive first-connect profile assignment (future UX, separate plan)
- Graph-based step scheduling (AUD-004, separate concern)
- Chain-wide rollback (AUD-003, separate concern)

---

## Critical Constraint: Device Identification

**Parsec local logs do not contain client device type, IP, OS, peer_id, or machine name.**

The only identifier is the Parsec username (`Username#1234`). Per-device recipe selection is handled by the recipe system itself: each recipe declares an optional `username` filter. When set, that recipe only fires for that user. When omitted, the recipe responds to all connection events.

There is no separate username-to-profile mapping layer. The recipe owns its trigger conditions. Users who connect from multiple devices need distinct Parsec accounts if they want different recipes per device.

This constraint was validated by examining the auto-parsec source code, Parsec's official documentation, and the `app_log_level` configuration options.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      Task Scheduler                              │
│                   (At Logon trigger)                              │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Watcher Process                               │
│                                                                  │
│  ┌────────────────┐    ┌──────────────┐    ┌─────────────────┐  │
│  │   Log Tailer   │───▶│ Event Router │───▶│ Recipe Matcher  │  │
│  │ (FSWatcher +   │    │ (regex match │    │ (user + mode →  │  │
│  │  FileStream)   │    │  + extract)  │    │  matching recipe)│  │
│  └────────────────┘    └──────┬───────┘    └────────┬────────┘  │
│                               │                     │            │
│                    ┌──────────▼─────────┐           │            │
│                    │  Session Tracker   │           │            │
│                    │ (connected users,  │           │            │
│                    │  grace periods,    │           │            │
│                    │  debounce)         │           │            │
│                    └──────────┬─────────┘           │            │
│                               │                     │            │
│                    ┌──────────▼─────────────────────▼─────────┐  │
│                    │           Recipe Dispatcher              │  │
│                    │  (background runspace → Invoke-Recipe)   │  │
│                    └─────────────────────────────────────────┘  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                   Configuration                            │  │
│  │  parsec-watcher.toml: log path, profiles, user bindings,  │  │
│  │  grace period, patterns, logging                           │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │                   State Persistence                        │  │
│  │  watcher-state.json: current_mode, active_sessions[],     │  │
│  │  last_log_position, watcher_started_at                     │  │
│  └────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Input | Output |
|---|---|---|---|
| **Log Tailer** | Monitor Parsec log file for new lines, handle rotation | File path | Raw log lines |
| **Event Router** | Match lines against patterns, extract user identity | Raw lines + regex config | Typed events (Connected/Disconnected/Attempt) |
| **Recipe Matcher** | Find recipes whose `username` filter and `initial_mode` match the event | Username + current mode + loaded recipes | Matching recipe |
| **Session Tracker** | Track active sessions, enforce grace period, debounce | Events | Filtered dispatch-worthy events |
| **Recipe Dispatcher** | Invoke recipe execution in background runspace | Recipe name | Execution result (logged) |
| **Configuration** | Load and validate watcher config from TOML | File path | Typed config object |
| **State Persistence** | Persist watcher state across restarts | State object | JSON file |

---

## Phases

### Phase 0: Empirical Validation (No Code)

**Goal**: Resolve all open questions from the research that cannot be answered without live testing on the target machine.

| Task | Method | Deliverable |
|---|---|---|
| 0.1 Capture live Parsec log lines | Connect from phone, observe `log.txt` | Exact log line format documented |
| 0.2 Validate username format | Check if `Username#1234` matches across account types | Confirmed regex pattern |
| 0.3 Test log rotation | Fill log to 1MB, observe behavior | Rotation type documented (truncate vs new file) |
| 0.4 Measure event latency | Compare Parsec UI event time to log entry timestamp | Latency range documented |
| 0.5 Test multi-client scenario | Connect two clients, disconnect one | Log disambiguation confirmed/denied |
| 0.6 Test verbose logging | Set `app_log_level = 2`, check for extra metadata | Additional fields documented or confirmed absent |
| 0.7 Validate FileSystemWatcher on log dir | Run basic watcher on `%APPDATA%\Parsec\`, verify events fire | FSWatcher viability confirmed |
| 0.8 Observe host behavior on disconnect | Disconnect Parsec, observe: does host lock? Does session persist? How long until stable? | Grace period default determined |
| 0.9 Test Parsec connect with multiple accounts | Connect from two devices with different accounts | Multi-account recipe matching validated |

**Exit criteria**: Log format documented, regex patterns finalized, rotation strategy chosen, grace period default determined.

### Phase 1: Configuration Schema and Recipe Username Filter

**Goal**: Define the watcher's configuration surface and extend the recipe schema with an optional `username` filter.

#### 1.1 Watcher Configuration Schema

Design the `parsec-watcher.toml` configuration file:

```toml
[watcher]
# Path to Parsec log file. "auto" detects per-user or per-machine install.
parsec_log_path = "auto"
# Milliseconds to wait after connect event before dispatching recipe.
apply_delay_ms = 3000
# Default grace period. Can be overridden per-recipe.
grace_period_ms = 10000
# Polling interval fallback if FileSystemWatcher is unreliable.
poll_interval_ms = 1000
# Log level for watcher's own logging: debug, info, warn, error.
log_level = "info"

[patterns]
# Regex patterns for Parsec log line matching.
# Group 1 must capture the username (e.g., "User#1234").
connect = '\]\s+(.+#\d+)\s+connected\.\s*$'
disconnect = '\]\s+(.+#\d+)\s+disconnected\.\s*$'
# Note: "trying to connect" was NOT observed in Parsec 150-102b service install.
# Omitted from default patterns. Can be re-added if validated on other versions.
```

#### 1.2 Recipe Schema Extension

Add optional `username` and `grace_period_ms` fields to recipe TOML:

```toml
[recipe]
name = "enter-mobile"
description = "Phone connection - portrait, high DPI"
username = "Phone#1234"           # Optional. If omitted, fires for any user.
grace_period_ms = 10000           # Optional. Overrides watcher default.
initial_mode = "DESKTOP"
target_mode = "MOBILE"
```

Dispatch logic: on connect event, the watcher scans all loaded recipes for those whose `username` matches (or is absent) AND whose `initial_mode` matches the current state. First match wins.

#### 1.3 Recipe Matcher Implementation

- `Read-ParsecWatcherConfig` — load and validate watcher TOML config
- `Find-ParsecMatchingRecipe` — given username + current mode + loaded recipes, return the first matching recipe
- `Test-ParsecWatcherConfig` — validate config structure, verify patterns compile
- Existing `Get-ParsecRecipe` already loads recipes — Recipe Matcher consumes its output

#### 1.4 Files

| File | Purpose |
|---|---|
| `src/ParsecEventExecutor/Private/Watcher/Config.ps1` | Watcher config loading and validation |
| `src/ParsecEventExecutor/Private/Watcher/RecipeMatcher.ps1` | Username + mode → matching recipe |
| `parsec-watcher.toml` | Default configuration file (project root, alongside recipes/) |
| `tests/WatcherConfig.Tests.ps1` | Config parsing and recipe matching tests |

### Phase 2: Log Tailer

**Goal**: Build a robust log tailing component that handles rotation and emits raw line events.

#### 2.1 Hybrid Tailer Design

The tailer combines `FileSystemWatcher` for reactivity with `FileStream` for precise position tracking:

1. On startup: record file size as `$lastPosition`
2. `FileSystemWatcher` on the log directory, filter `log.txt`, `Changed` event
3. On `Changed`: open with `FileShare.ReadWrite`, seek to `$lastPosition`, read new lines
4. Rotation detection: if current file size < `$lastPosition`, reset to 0
5. Emit each new line via `New-Event -SourceIdentifier 'Parsec.LogLine'`

Fallback: if FSWatcher proves unreliable (validated in Phase 0.7), implement poll loop with configurable interval.

#### 2.2 Startup Reconciliation

On watcher startup, scan the last N lines of the log (configurable, default 100) to detect sessions that began while the watcher was not running. If an unmatched connect event is found for a user:
- Set initial state to the appropriate profile
- Do NOT re-dispatch the connect recipe (the display may already be configured)
- Log a warning: "Detected active session for User#1234, assuming current state is correct"

#### 2.3 Files

| File | Purpose |
|---|---|
| `src/ParsecEventExecutor/Private/Watcher/LogTailer.ps1` | FileSystemWatcher + FileStream tailer |
| `tests/LogTailer.Tests.ps1` | Tailer tests with mock log files (rotation, new lines, empty) |

### Phase 3: Event Router and Session Tracker

**Goal**: Parse raw log lines into typed events, track session state, enforce grace periods.

#### 3.1 Event Router

- Subscribe to `Parsec.LogLine` engine events
- Match each line against configured regex patterns
- Extract username from capture group 1
- Emit typed events: `Parsec.Connected`, `Parsec.Disconnected`, `Parsec.Attempt`
- Each event carries `MessageData = @{ User = 'Username#1234'; Timestamp = [datetime] }`

#### 3.2 Session Tracker

Maintains an in-memory dictionary of active sessions:

```powershell
$activeSessions = @{
    'Phone#1234' = @{
        Profile = 'mobile'
        ConnectedAt = [datetime]
        DisconnectTimer = $null  # grace period timer, if disconnect received
    }
}
```

**Connect logic**:
1. If user already in `$activeSessions`: ignore (duplicate connect, Parsec sometimes logs multiple)
2. Resolve profile via `Resolve-ParsecProfile`
3. Wait `apply_delay_ms` (configurable, accounts for Parsec display negotiation)
4. Dispatch connect recipe
5. Add to `$activeSessions`

**Disconnect logic**:
1. If user not in `$activeSessions`: ignore (orphaned disconnect)
2. Start grace period timer (`grace_period_ms`)
3. If user reconnects before timer expires: cancel timer, log "reconnect within grace period"
4. If timer expires: dispatch disconnect recipe, remove from `$activeSessions`

**State transition rules**:
- First connect with no active sessions: dispatch connect recipe
- Connect while another user is already connected: log warning, do NOT dispatch (first connection owns the mode)
- Last user disconnects (after grace period): dispatch disconnect recipe
- Watcher shutdown: persist `$activeSessions` to `watcher-state.json`

#### 3.3 Files

| File | Purpose |
|---|---|
| `src/ParsecEventExecutor/Private/Watcher/EventRouter.ps1` | Log line → typed event |
| `src/ParsecEventExecutor/Private/Watcher/SessionTracker.ps1` | Session state, grace period, dispatch decisions |
| `tests/EventRouter.Tests.ps1` | Pattern matching tests |
| `tests/SessionTracker.Tests.ps1` | Session lifecycle, grace period, multi-user tests |

### Phase 4: Recipe Dispatcher

**Goal**: Bridge the watcher to the existing recipe engine, dispatching execution in a background runspace to avoid blocking the event loop.

#### 4.1 Background Dispatch

Recipe execution can take seconds to minutes (display topology changes, readiness probes, retries). The watcher's event loop must not block during execution.

Pattern:
```powershell
# Dispatch to background runspace
$runspace = [runspacefactory]::CreateRunspace()
$runspace.Open()
$ps = [powershell]::Create().AddScript({
    param($recipeName)
    Import-Module ParsecEventExecutor
    Invoke-ParsecRecipe -Name $recipeName
}).AddParameter('recipeName', $recipe)
$ps.Runspace = $runspace
$handle = $ps.BeginInvoke()
# Store $ps and $handle for completion tracking
```

#### 4.2 Execution Guard

- Only one recipe may execute at a time (mutex or flag)
- If a new event arrives while a recipe is executing: queue it, process after current completes
- If a disconnect arrives while a connect recipe is executing: cancel is not safe (partial state) — queue the disconnect and let connect complete first

#### 4.3 Result Logging

- On completion: read result from `$ps.EndInvoke($handle)`, log outcome
- On failure: log error, update watcher state to reflect partial/failed transition
- Leverage existing event journaling (`Write-ParsecEventRecord`) — the recipe engine already writes events

#### 4.4 Files

| File | Purpose |
|---|---|
| `src/ParsecEventExecutor/Private/Watcher/Dispatcher.ps1` | Background runspace dispatch, execution guard, result handling |
| `tests/Dispatcher.Tests.ps1` | Dispatch lifecycle, queuing, guard tests |

### Phase 5: Watcher Main Loop and Lifecycle

**Goal**: Wire all components into a single long-running process with clean startup/shutdown.

#### 5.1 Main Loop

```
Start-ParsecWatcher
  ├── Load configuration (parsec-watcher.toml)
  ├── Validate config (recipes exist, patterns compile, profiles resolve)
  ├── Initialize state (load watcher-state.json or create fresh)
  ├── Detect Parsec log path (auto-detect or configured)
  ├── Startup reconciliation (scan last N lines for active sessions)
  ├── Start Log Tailer (FileSystemWatcher + FileStream)
  ├── Register Event Router (subscribe to Parsec.LogLine)
  ├── Register Session Tracker (subscribe to Parsec.Connected/Disconnected)
  ├── Enter event loop (Wait-Event with cleanup on Ctrl+C / termination)
  └── Shutdown: persist state, unregister events, dispose watcher
```

#### 5.2 Public Command

- `Start-ParsecWatcher` — exported function, entry point for the watcher
- Parameters: `-ConfigPath` (optional, default: project root `parsec-watcher.toml`), `-Verbose`, `-WhatIf` (dry run — log what would be dispatched without executing recipes)

#### 5.3 Task Scheduler Registration

- `Register-ParsecWatcherTask` — helper to create the Task Scheduler entry
- Parameters: `-TaskName` (default: `ParsecEventWatcher`), `-ConfigPath`
- Creates: logon trigger, restart-on-failure (3 retries, 1-minute interval), hidden window

#### 5.4 Files

| File | Purpose |
|---|---|
| `src/ParsecEventExecutor/Private/Watcher/Main.ps1` | Watcher main loop and lifecycle |
| `src/ParsecEventExecutor/Public/Start-ParsecWatcher.ps1` | Exported entry point |
| `src/ParsecEventExecutor/Public/Register-ParsecWatcherTask.ps1` | Task Scheduler helper |
| `tests/Watcher.Tests.ps1` | Integration tests with mock log files |

### Phase 6: Testing and Hardening

**Goal**: Comprehensive test coverage and edge case handling.

#### 6.1 Test Matrix

| Scenario | Test Type |
|---|---|
| Config parsing — valid TOML, all fields | Unit |
| Config parsing — missing fields, defaults | Unit |
| Config parsing — invalid recipe reference | Unit |
| Profile resolution — known user | Unit |
| Profile resolution — unknown user → default | Unit |
| Log tailer — new lines appended | Unit (mock file) |
| Log tailer — file rotation (truncate) | Unit (mock file) |
| Log tailer — file rotation (new file) | Unit (mock file) |
| Event router — connect pattern match | Unit |
| Event router — disconnect pattern match | Unit |
| Event router — non-matching line (noise) | Unit |
| Session tracker — single connect/disconnect | Unit |
| Session tracker — grace period cancel on reconnect | Unit |
| Session tracker — multi-user first-wins | Unit |
| Session tracker — startup reconciliation | Unit |
| Dispatcher — successful recipe dispatch | Integration (mocked recipe) |
| Dispatcher — execution guard (queue while busy) | Integration |
| Full watcher — mock log file → recipe invocation | Integration |

#### 6.2 Edge Cases to Handle

| Edge Case | Strategy |
|---|---|
| Parsec not installed (no log file) | Fail startup with clear error message |
| Log file empty on startup | Start tailing from position 0 |
| Rapid connect/disconnect (< 1 second) | Grace period absorbs; only dispatches if disconnect persists |
| Connect event during active recipe execution | Queue; process after current recipe completes |
| Watcher killed during recipe execution | On restart, reconcile from log and executor-state.json |
| Log file locked by Parsec during read | FileShare.ReadWrite handles this; retry on IOException |
| Config file syntax error | Fail startup with parse error and line number |

---

## File Summary

### New Files

| Path | Phase |
|---|---|
| `parsec-watcher.toml` | 1 |
| `src/ParsecEventExecutor/Private/Watcher/Config.ps1` | 1 |
| `src/ParsecEventExecutor/Private/Watcher/RecipeMatcher.ps1` | 1 |
| `src/ParsecEventExecutor/Private/Watcher/LogTailer.ps1` | 2 |
| `src/ParsecEventExecutor/Private/Watcher/EventRouter.ps1` | 3 |
| `src/ParsecEventExecutor/Private/Watcher/SessionTracker.ps1` | 3 |
| `src/ParsecEventExecutor/Private/Watcher/Dispatcher.ps1` | 4 |
| `src/ParsecEventExecutor/Private/Watcher/Main.ps1` | 5 |
| `src/ParsecEventExecutor/Public/Start-ParsecWatcher.ps1` | 5 |
| `src/ParsecEventExecutor/Public/Register-ParsecWatcherTask.ps1` | 5 |
| `tests/WatcherConfig.Tests.ps1` | 1 |
| `tests/LogTailer.Tests.ps1` | 2 |
| `tests/EventRouter.Tests.ps1` | 3 |
| `tests/SessionTracker.Tests.ps1` | 3 |
| `tests/Dispatcher.Tests.ps1` | 4 |
| `tests/Watcher.Tests.ps1` | 6 |

### Modified Files

| Path | Change | Phase |
|---|---|---|
| `src/ParsecEventExecutor/ParsecEventExecutor.psd1` | Add new exported functions | 5 |
| `src/ParsecEventExecutor/ParsecEventExecutor.psm1` | Dot-source Watcher/ files | 5 |
| `docs/README.md` | Add research domain 07 | 1 |
| `docs/plan/implementation-plan.md` | Add pointer to this plan | 1 |

---

## Dependencies

| Dependency | Status | Notes |
|---|---|---|
| PSToml module | Available | `Install-PSResource -Name PSToml` — already used implicitly by project's TOML handling |
| FileSystemWatcher (.NET) | Built-in | `System.IO.FileSystemWatcher`, no external dependency |
| Existing recipe engine | Functional | `Invoke-ParsecRecipe`, `Get-ParsecRecipe` — tested and working |
| Existing state persistence | Functional | `executor-state.json`, event journaling — tested and working |
| Task Scheduler cmdlets | Built-in | `ScheduledTasks` module, ships with Windows |

---

## ADR Implications

This plan extends but does not contradict the existing ADRs:

| ADR | Extension |
|---|---|
| ADR-1 (Event Detection) | Confirms log tailing; specifies hybrid FSWatcher+FileStream over raw `Get-Content -Wait` |
| ADR-5 (Daemon Lifecycle) | Confirms Task Scheduler; adds `Register-ParsecWatcherTask` helper |
| ADR-7 (Configuration) | Extends config from single JSON to TOML with profiles and user bindings |
| New: Per-device binding | Not covered by existing ADRs — requires new ADR if approved |

---

## Decisions (Finalized 2026-03-14)

All architectural decisions have been made and recorded in [`docs/adr/2026-03-14-parsec-state-watcher.md`](../adr/2026-03-14-parsec-state-watcher.md).

| # | Decision | Resolution |
|---|---|---|
| 1 | Per-device recipe binding | Username filter in recipe TOML, no mapping table (ADR-8) |
| 2 | Grace period | Configurable, default 10 seconds, per-recipe override. Validated: no lock screen, Parsec auto-reverts resolution |
| 3 | Multi-user policy | First connection wins |
| 4 | Watcher command | New `Start-ParsecWatcher`; `Start-ParsecExecutor` may be deprecated if superseded |
| 5 | Config format | TOML (consistent with recipes) |
| 6 | ADR | Written: ADR-8 (recipe username filter) and ADR-9 (FSWatcher+FileStream) |
