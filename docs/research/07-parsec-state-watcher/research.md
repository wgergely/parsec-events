# Parsec State Watcher: Log Tailing, Event Dispatch, and Per-Device Recipe Binding

## Status: Research Complete — Architecture Ready for Planning

## Problem Statement

The Parsec Event Executor has a functional recipe engine (20 ingredients, 8 domains, step orchestration with dependency gating, compensation, and verification) but no mechanism to trigger recipes automatically. Today, `Start-ParsecExecutor -EventName SwitchToMobile` must be invoked manually. The system needs a persistent watcher that:

1. Tails the Parsec log file for connection events.
2. Identifies the connecting user.
3. Maps the user to a device profile (mobile, laptop, desktop peer, etc.).
4. Dispatches the appropriate recipe for that profile.
5. Reverses the recipe on disconnect.

Additionally, the original ADR assumed a single binary mobile/desktop toggle. The scope must be extended to support **per-user, per-device recipe binding** — different connecting clients may require different recipes.

---

## Research Findings

### 1. Parsec Log File Format and Event Signals

#### Log File Location

| Install Type | Path |
|---|---|
| Per-user | `%APPDATA%\Parsec\log.txt` |
| Per-machine (service) | `%ProgramData%\Parsec\log.txt` |

#### Log Entry Format

Parsec log lines follow the pattern:

```
[<level> <timestamp>] <message>
```

Where level is a single character/digit (e.g., `D`, `0`, `3`) and timestamp is `YYYY-MM-DD HH:MM:SS`.

Connection-related entries (confirmed by auto-parsec source and community reports):

```
[D 2026-03-14 10:37:03] Username#1234 is trying to connect to your computer.
[D 2026-03-14 10:37:05] Username#1234 connected.
[D 2026-03-14 10:37:45] Username#1234 disconnected.
```

The auto-parsec project extracts the username using regex `\]\s(.+#\d+)` and detects event type via string suffix:
- `.EndsWith(" connected.")` — successful connection
- `.EndsWith("disconnected.")` — disconnection
- `.EndsWith("is trying to connect to your computer.")` — connection attempt

#### Log Rotation Behavior

- Log file rotates (cycles) when it reaches **1 MB**.
- Log is **not cleared** on Parsec restart (confirmed since May 2021).
- During active streams, high-frequency status lines are written: `[0] FPS:60.0/0, L:8.5/10.0, B:15.5/50.0, N:0/0/0`.

#### Logging Verbosity

- Default: `app_log_level = 1`
- Verbose: `app_log_level = 2` — additional connection initialization detail (may impact performance)

### 2. What Parsec Logs Do NOT Contain

**This is the critical constraint for per-device recipe binding.**

The local `log.txt` file does **not** contain:
- Client device type (mobile, desktop, tablet, console)
- Client operating system
- Client peer_id
- Client machine name or hostname
- Client IP address
- Client screen resolution or physical screen size

The **only identifier** available from the log is the Parsec username in `Username#1234` format.

**Implication**: Per-device recipe binding cannot be inferred from log data alone. It must be achieved through **username-to-profile mapping in configuration**. Since a single Parsec account can be logged in on multiple devices, users who connect from both a phone and a laptop would need distinct Parsec accounts, or the system must provide a manual override/prompt mechanism.

#### Enterprise/Teams Audit Log API

Parsec Teams/Enterprise tiers expose a JSON audit log via admin dashboard with potentially richer metadata. This is not available on personal plans and is not a real-time local data source. **Not viable for this project.**

#### Parsec SDK

The Parsec SDK (`parsec.app/docs/sdk`) exposes `ParsecLogLevel` and richer connection metadata programmatically, but requires C integration and linking against the SDK. This is a future extensibility path, not a practical option for a PowerShell-based system.

### 3. Reference Implementations

#### auto-parsec (Borgotto/auto-parsec)

**Architecture**: Single main script with function-override pattern for pluggable actions.

| Aspect | Implementation |
|---|---|
| Log detection | `Get-Content -Wait -Tail` in a polling loop |
| User extraction | Regex `\]\s(.+#\d+)` captures `Username#1234` |
| Event dispatch | Three stub functions: `OnConnect($user)`, `OnDisconnect($user)`, `OnConnectAttempt($user)` |
| Override pattern | Consumer scripts define functions as `ReadOnly` before dot-sourcing main script |
| Rotation handling | IOException catch + retry loop |
| Connected user tracking | `ArrayList` of currently connected usernames |
| Multi-user support | Tracks multiple connected users; disconnects are per-user |

**Weaknesses**:
- No device type identification (only username)
- `Get-Content -Wait` has a fixed 1-second polling interval
- O(n²) unread line calculation on startup
- No exponential backoff or structured error handling
- No state persistence across restarts

#### MonitorSwapAutomation (Nonary/MonitorSwapAutomation)

**Architecture**: Background PowerShell process with named pipes for IPC, polling-based stream detection for Sunshine (not Parsec).

| Aspect | Implementation |
|---|---|
| Event detection | Polls `Get-NetUDPEndpoint` on Sunshine process |
| Profile system | Two fixed profiles: `Primary.xml` and `Dummy.xml` (NOT per-device) |
| Grace period | Configurable delay (default 900s) before treating disconnect as final |
| IPC | `NamedPipeServerStream`/`NamedPipeClientStream` for cross-process events |
| Event engine | `Register-EngineEvent` + `New-Event` for pub-sub |
| Instance management | Mutex to prevent duplicate watchers |

**Key takeaway**: Grace period pattern is valuable — prevents profile thrashing on brief disconnects. Named pipe IPC is overengineered for our use case. Does NOT support per-device profiles.

#### auto-parsec-vdd (michyprima/auto-parsec-vdd)

Automatically creates/destroys Parsec virtual displays on connect/disconnect. Demonstrates the log-tailing-to-action pipeline with VDD integration. Relevant as a future ingredient (virtual display management) but not directly applicable to the watcher architecture.

### 4. Log Tailing Approaches in PowerShell

#### Approach A: Get-Content -Wait -Tail (Current ADR recommendation)

```powershell
Get-Content -Path $logPath -Wait -Tail 0 | ForEach-Object { ... }
```

**Pros**: Simple, one-liner, native cmdlet.
**Cons**:
- Fixed 1-second poll interval (not configurable)
- Breaks on file rotation (holds stale file handle)
- Cannot detect file truncation/replacement
- Requires try/catch + retry loop for rotation recovery

#### Approach B: FileSystemWatcher + Position-Tracked FileStream

```powershell
$watcher = [System.IO.FileSystemWatcher]::new($directory, 'log.txt')
$watcher.EnableRaisingEvents = $true
Register-ObjectEvent -InputObject $watcher -EventName Changed -Action {
    # Read from last known position to end of file
    # Detect rotation by checking if file size < last position
}
```

**Pros**:
- Reacts to actual file changes (not polling)
- Full control over file handle and position tracking
- Can detect rotation by comparing file size or creation time
- No missed events during processing

**Cons**:
- More code to write and maintain
- FileSystemWatcher tells you *that* a file changed, not *what* changed — still need position tracking
- Event handlers run in the main runspace (single-threaded)

#### Approach C: Hybrid (Recommended)

Use `FileSystemWatcher` for change notification, `FileStream` with `FileShare.ReadWrite` for reading, and explicit position tracking. On each `Changed` event:

1. Open file with `FileShare.ReadWrite` (non-blocking)
2. Seek to last known position
3. Read new content line by line
4. If file size < last position, assume rotation: reset position to 0 and re-read
5. Update last position

This provides the robustness of position tracking with the reactivity of filesystem events, without the 1-second polling latency.

#### Approach D: .NET FileStream Poll Loop (Fallback)

If FileSystemWatcher proves unreliable (known issues on some file systems), fall back to a manual poll loop with configurable interval:

```powershell
while ($true) {
    $currentSize = (Get-Item $logPath).Length
    if ($currentSize -gt $lastPosition) { ... read delta ... }
    elseif ($currentSize -lt $lastPosition) { ... rotation detected ... }
    Start-Sleep -Milliseconds $pollInterval
}
```

### 5. Per-Device Recipe Binding Design

> **Note**: The options below were evaluated during research. **ADR-8 decided on a different approach**: recipes declare an optional `username` field directly, with no separate mapping layer. See `docs/adr/2026-03-14-parsec-state-watcher.md`.

Since Parsec logs only expose `Username#1234`, the per-device mapping must live in configuration. The design space explored:

#### Option 1: Username → Profile → Recipe (Rejected — unnecessary indirection)

```toml
[profiles.mobile]
description = "Phone connection - single portrait display"
recipe = "enter-mobile"
disconnect_recipe = "return-desktop"

[profiles.laptop]
description = "Laptop connection - single landscape display"
recipe = "enter-laptop"
disconnect_recipe = "return-desktop"

[profiles.default]
description = "Fallback for unknown users"
recipe = "enter-mobile"
disconnect_recipe = "return-desktop"

[users]
"MyPhone#1234" = "mobile"
"MyLaptop#5678" = "laptop"
```

**Advantages**: Clean separation of concerns — profiles define behavior, user mappings are declarative, recipes are reusable.

**Trade-off**: Requires a distinct Parsec account per device if the same person connects from multiple devices (since username is the only identifier).

#### Option 2: Regex-Based User Matching

```toml
[[bindings]]
pattern = ".*Phone.*"
profile = "mobile"

[[bindings]]
pattern = ".*Laptop.*"
profile = "laptop"

[[bindings]]
pattern = ".*"
profile = "default"
```

**Advantage**: Flexible matching without enumerating every username.
**Risk**: Regex matching on usernames is fragile and requires users to name their Parsec accounts predictably.

#### Option 3: First-Connect Prompt (Interactive)

On first connection from an unrecognized user, prompt (via toast notification or similar) asking which profile to assign. Persist the mapping for future connections.

**Advantage**: No upfront configuration needed.
**Risk**: Requires interactive UI integration; complex for a background service.

#### Recommendation

**Option 1** is the pragmatic choice. Option 2 can be layered on as sugar. Option 3 is future work.

### 6. PowerShell Daemon Lifecycle

#### Task Scheduler (Current ADR) vs NSSM

| Aspect | Task Scheduler | NSSM |
|---|---|---|
| Runs in user session | Yes (at logon trigger) | Configurable (default: Session 0) |
| Auto-restart on crash | Yes (RestartCount/Interval) | Yes (built-in) |
| Survives logoff | No | Yes (runs as service) |
| Display API access | Yes (Session 1+) | Requires `CreateProcessAsUser` workaround |
| Admin required | No (user tasks) | Yes (service install) |
| PowerShell 7 support | Yes | Yes |
| Window flash issue | Yes (brief pwsh window) | No (service process) |

**Decision**: Task Scheduler remains correct for this project. The display configuration APIs require user-session execution (Session 1+). NSSM running in Session 0 would need workarounds. The watcher only needs to run while the user is logged in — Task Scheduler's "at logon" trigger matches this lifecycle exactly.

#### Restart and Recovery

```powershell
$settings = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
```

Combined with state persistence (executor-state.json already exists), the watcher can reconcile on restart by scanning the last N lines of the Parsec log.

### 7. Event Architecture: Internal Dispatch

The existing executor already has:
- `Write-ParsecEventRecord` — event journaling
- `executor-run-started`, `executor-step-completed`, `executor-run-completed` events
- Linear dependency-gated step execution

What needs to be added:
- **Watcher loop** — the outer process that tails the log
- **Event router** — matches log lines to event types and extracts user identity
- **Profile resolver** — maps `Username#1234` → profile → recipe
- **Dispatch bridge** — calls `Start-ParsecExecutor` (or `Invoke-ParsecRecipe` directly) with the resolved recipe
- **Session tracker** — maintains list of active sessions for multi-user disconnect handling
- **Debounce/grace period** — configurable delay before treating disconnect as final

#### PowerShell Event Bus Pattern

Use `Register-EngineEvent` / `New-Event` for internal dispatch:

```powershell
# Publisher (log tailer)
New-Event -SourceIdentifier 'Parsec.Connected' -MessageData @{ User = 'Phone#1234' }

# Subscriber (recipe dispatcher)
Register-EngineEvent -SourceIdentifier 'Parsec.Connected' -Action {
    $user = $Event.MessageData.User
    $profile = Resolve-ParsecProfile -User $user
    Invoke-ParsecRecipe -Name $profile.Recipe
}
```

This decouples the log tailer from recipe execution, enabling testability and future extensibility (e.g., additional event sources like WMI display change confirmation).

---

## Open Questions Requiring Empirical Validation

| # | Question | Validation Method | Priority |
|---|---|---|---|
| 1 | Exact Parsec log line format on current version | Capture live connect/disconnect cycle | **Critical** |
| 2 | Does the username format always match `\w+#\d+`? | Test with special characters in Parsec display name | High |
| 3 | Log rotation: does Parsec create a new file or truncate in place? | Monitor file identity (creation time, size) across rotation | High |
| 4 | Latency between actual event and log entry | Timestamp comparison during live test | Medium |
| 5 | Multiple simultaneous clients: are disconnect events unambiguous? | Connect two clients, disconnect one, observe log | Medium |
| 6 | Does `app_log_level = 2` expose device metadata? | Set verbose logging, capture output | Medium |
| 7 | FileSystemWatcher reliability on the Parsec log directory | Run watcher for 24+ hours, verify no missed events | Medium |

---

## Key Constraints and Risks

| Constraint | Impact | Mitigation |
|---|---|---|
| **No device type in logs** | Cannot auto-detect mobile vs desktop client | Username-to-profile mapping in config |
| **Log rotation at 1 MB** | `Get-Content -Wait` breaks; need robust tailing | Hybrid FileSystemWatcher + FileStream approach |
| **1-second poll ceiling with Get-Content** | Acceptable latency but not configurable | FileSystemWatcher provides faster reaction |
| **Single Parsec account per device** | Users connecting from multiple devices need multiple accounts | Document as setup requirement; future: interactive first-connect binding |
| **PowerShell event handlers are single-threaded** | Long recipe execution blocks the event loop | Dispatch recipe execution to a background runspace |
| **Task Scheduler window flash** | Brief pwsh window on startup | VBScript wrapper or `-WindowStyle Hidden` (known imperfection) |

---

## References

### Reference Project Grounding (Source Code Audited 2026-03-14)

| Project | Service Lifecycle | Event Detection | Instance Guard | File Logging | Auto-Restart |
|---|---|---|---|---|---|
| [auto-parsec](https://github.com/Borgotto/auto-parsec) | None (manual Task Scheduler) | `Get-Content -Wait` (blocks, no rotation handling) | None | None | None |
| [MonitorSwapAutomation](https://github.com/Nonary/MonitorSwapAutomation) | Sunshine `global_prep_cmd` (session-scoped) | UDP endpoint polling (1s loop) | Named pipes + mutex | `Start-Transcript` (10 files) | Re-triggered by Sunshine |
| [auto-parsec-vdd](https://github.com/michyprima/auto-parsec-vdd) | None (manual Task Scheduler) | WMI monitor polling (no log tailing) | None | None | None |
| [ParsecVDA-Always-Connected](https://github.com/timminator/ParsecVDA-Always-Connected) | **winsw** (proper Windows Service) | WMI + Event Log subscription | Service singleton | Log file | Service restart |

**Key observations from source audit:**
- No reference project uses PowerShell's `FileSystemWatcher` + `FileStream` (our approach is more robust than any reference)
- Only ParsecVDA-AC implements proper service lifecycle via winsw; all others require manual setup
- MonitorSwapAutomation is the only one with instance guarding (named pipes + mutex); our mutex approach is equivalent
- MonitorSwapAutomation's `Start-Transcript` log rotation (keep 10) is the pattern we adopted
- None of the Parsec-specific projects (auto-parsec, auto-parsec-vdd) have crash recovery — they rely on Task Scheduler restart-on-failure, which is our approach

### Primary Sources
- [auto-parsec — PowerShell Parsec automation](https://github.com/Borgotto/auto-parsec)
- [MonitorSwapAutomation — Sunshine display switching](https://github.com/Nonary/MonitorSwapAutomation)
- [auto-parsec-vdd — Parsec VDD automation](https://github.com/michyprima/auto-parsec-vdd)
- [parsec-vdd — Virtual display driver CLI](https://github.com/nomi-san/parsec-vdd)

### Parsec Documentation
- [Stream Overlay, Stats, and Logging](https://support.parsec.app/hc/en-us/articles/32381603663636-Stream-Overlay-Stats-and-Logging)
- [All Advanced Configuration Options](https://support.parsec.app/hc/en-us/articles/360001562772-All-Advanced-Configuration-Options)
- [Team Audit Logs](https://support.parsec.app/hc/en-us/articles/32381584005268-Team-Audit-Logs)
- [Parsec App for Windows](https://support.parsec.app/hc/en-us/articles/32381199341716-Parsec-App-for-Windows)
- [Components and Connection Sequence](https://support.parsec.app/hc/en-us/articles/32361410290324-Components-and-Connection-Sequence)

### PowerShell Patterns
- [FileSystemWatcher best practices (powershell.one)](https://powershell.one/tricks/filesystem/filesystemwatcher)
- [Reusable File System Event Watcher (Microsoft DevBlogs)](https://devblogs.microsoft.com/powershell-community/a-reusable-file-system-event-watcher-for-powershell/)
- [Register-EngineEvent (Microsoft Learn)](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/register-engineevent?view=powershell-7.5)
- [Runspace Pools (markw.dev)](https://markw.dev/runspaces-explained/)
- [Thread synchronization in PowerShell (Dave Wyatt)](https://davewyatt.wordpress.com/2014/04/06/thread-synchronization-in-powershell/)

### Windows Infrastructure
- [Task Scheduler PowerShell cmdlets (Microsoft Learn)](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/)
- [NSSM — Non-Sucking Service Manager](https://nssm.cc/usage)
- [PSToml — TOML for PowerShell](https://github.com/jborean93/PSToml)
