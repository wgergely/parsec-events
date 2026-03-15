# Architecture Decision Record: Parsec State Watcher

**Date**: 2026-03-14
**Status**: Accepted
**Author**: Gergely Wootsch
**Research**: [`docs/research/07-parsec-state-watcher/research.md`](../research/07-parsec-state-watcher/research.md)
**Plan**: [`docs/plan/2026-03-14-parsec-state-watcher.md`](../plan/2026-03-14-parsec-state-watcher.md)

---

## Context

The Parsec Event Executor has a functional recipe engine (20 ingredients, 8 domains, dependency-gated step execution) but no automatic event detection. Recipes must be invoked manually via `Start-ParsecExecutor -EventName SwitchToMobile`. The system needs a persistent watcher that monitors Parsec's log file, detects connection events, and dispatches the appropriate recipe.

Two architectural questions require binding decisions:

1. How should per-device recipe selection work, given that Parsec logs do not expose device type?
2. How should the log file be tailed robustly, given known limitations of `Get-Content -Wait`?

---

## ADR-8: Per-Device Recipe Binding via Username Filter in Recipes

### Decision

Recipes declare an optional `username` field. When present, the recipe only fires for connections from that specific Parsec user. When absent, the recipe fires for any connection event. There is no separate username-to-profile mapping layer.

### Options Considered

| Option | Verdict | Reason |
|---|---|---|
| Username filter in recipe | **Chosen** | No indirection; the recipe owns its trigger conditions; simple and declarative |
| Username → profile → recipe mapping table | Rejected | Unnecessary indirection that "doubles back" — maps username to a name that maps to another name. Extra config surface for no functional gain |
| Regex-based username matching | Rejected | Fragile; depends on predictable account naming conventions; adds complexity without clear benefit |
| Interactive first-connect prompt | Deferred | Requires UI integration; out of scope for initial implementation |

### Design

In recipe TOML:

```toml
[recipe]
name = "enter-mobile"
description = "Phone connection - portrait, high DPI"
username = "Phone#1234"           # Optional. If omitted, fires for any user.
initial_mode = "DESKTOP"
target_mode = "MOBILE"
```

Dispatch logic in the watcher:

1. Parsec log line matched → username extracted (e.g., `Phone#1234`)
2. Watcher scans all loaded recipes for those whose `username` matches (or is absent)
3. Among matching recipes, filter by `initial_mode` matching current state
4. First matching recipe is dispatched

When no `username` is set on any recipe, the system behaves as a simple two-state toggle responding to all connections — preserving backward compatibility with the existing `enter-mobile.toml` and `return-desktop.toml`.

### Consequences

- Users who connect from multiple devices need distinct Parsec accounts (one per device) if they want different recipes per device.
- If multiple recipes match the same event (same username or both unfiltered, same initial_mode), the first match wins. Recipe loading order becomes significant — this should be documented.
- The Profile Resolver component from the original plan is eliminated entirely, simplifying the architecture.

### Constraint

Parsec's local `log.txt` does not contain client device type, IP, OS, peer_id, or machine name. The username (`Username#1234` format) is the only identifier available. This was validated by examining the auto-parsec source code, Parsec's official documentation, and the `app_log_level` configuration options. The Enterprise/Teams audit log API exposes richer metadata but is not available on personal plans and is not a real-time local data source.

---

## ADR-9: Log Tailing via FileSystemWatcher + FileStream (Replacing Get-Content -Wait)

### Decision

Replace the originally proposed `Get-Content -Wait -Tail` approach with a hybrid `FileSystemWatcher` + `FileStream` implementation for Parsec log monitoring.

### Options Considered

| Option | Verdict | Reason |
|---|---|---|
| FileSystemWatcher + FileStream | **Chosen** | Handles rotation; reactive (not polling); full control over file position; robust |
| `Get-Content -Wait -Tail` | Rejected | Breaks on log rotation (stale file handle); fixed 1-second poll; cannot detect truncation |
| Pure FileSystemWatcher | Insufficient | Notifies *that* a file changed, not *what* changed; still needs position tracking |
| Pure polling FileStream loop | Fallback | Works but wastes CPU when idle; configurable interval is an advantage over `Get-Content` |
| .NET `LogFile` / third-party library | Rejected | Unnecessary dependency; the hybrid approach is straightforward |

### Design

The hybrid tailer operates as follows:

1. **Initialization**: Open `log.txt` with `FileShare.ReadWrite` (non-blocking, Parsec keeps the file open). Record initial file size as `$lastPosition`.

2. **Change detection**: A `FileSystemWatcher` monitors the log file's parent directory for `Changed` events on `log.txt`. This provides reactive notification without polling.

3. **Delta reading**: On each `Changed` event, seek to `$lastPosition`, read all new content line by line, update `$lastPosition`.

4. **Rotation detection**: If current file size < `$lastPosition`, the file was rotated (Parsec rotates at 1 MB). Reset `$lastPosition` to 0 and re-read the entire file.

5. **Fallback**: If `FileSystemWatcher` proves unreliable on the target filesystem (validated in Phase 0), degrade to a manual poll loop with configurable interval (default 1000ms).

6. **Event emission**: Each new line is published via `New-Event -SourceIdentifier 'Parsec.LogLine'`, decoupling the tailer from downstream processing.

### Consequences

- More code than the `Get-Content -Wait` one-liner, but fundamentally more reliable for a long-running watcher.
- File rotation is handled gracefully instead of crashing.
- Latency is bounded by filesystem event delivery (typically sub-100ms) rather than a fixed 1-second poll.
- The `FileSystemWatcher` has known edge cases on network drives and cloud-synced folders, but `%APPDATA%\Parsec\` is a local path — these issues do not apply.
- The tailer is testable in isolation with mock log files.

### Validation (Completed 2026-03-14)

- **FileSystemWatcher**: Confirmed working on `C:\ProgramData\Parsec\`. `Changed` and `Renamed` events fire reliably. Debounce (500ms) required to coalesce duplicate events. Must subscribe to `Error` event and recreate watcher on `InternalBufferOverflowException`.
- **Log rotation**: Parsec uses numbered rotation — `log.txt` → `log.1.txt`, new `log.txt` created. Subscribe to `Created` event to detect rotation and reset file position.
- **`Get-Content -Wait` memory leak**: Confirmed via PowerShell issue [#20892](https://github.com/PowerShell/PowerShell/issues/20892) — 16 GB+ RAM consumed overnight. Validates rejection of this approach.

---

## ADR-10: Parsec Resolution Auto-Matching Is Complementary

### Decision

Keep `server_resolution_x/y = 65535` (use client resolution). The recipe engine cooperates with Parsec's native resolution handling rather than fighting it.

### Rationale

Parsec auto-matches the client's resolution on connect and auto-reverts on disconnect. The recipe engine handles settings Parsec does NOT manage: DPI scaling, text scaling, orientation, theme, app lifecycle. The `apply_delay_ms` wait allows Parsec to finish its display negotiation before the recipe runs.

If Parsec crashes and fails to revert, the `return-desktop` recipe's snapshot restore covers the recovery path.

### Consequence

ADR-6 ("disable Parsec's auto-resolution") is **revised**. The original recommendation assumed a race condition. Empirical observation shows Parsec's negotiation completes within 1-2 seconds, and the configurable delay absorbs this. Disabling auto-resolution would force the recipe to handle resolution from scratch, adding complexity for no benefit.

Source: [Force A Server Resolution Change](https://support.parsec.app/hc/en-us/articles/32361385826068-Force-A-Server-Resolution-Change)

---

## Additional Decisions (Captured From Planning and Phase 0)

### Multi-User Policy: First Connection Wins

When multiple Parsec clients connect, the first connection's recipe takes effect. Subsequent connections are logged but do not trigger recipe changes. Desktop restore only occurs when the **last** client disconnects (after grace period). This aligns with Parsec's own behavior where the first owner-client sets the resolution.

### Grace Period: Configurable, Default 10 Seconds

The disconnect grace period is configurable with a runtime default (10 seconds) and per-recipe override. Empirical validation confirmed:
- Host does NOT lock screen on disconnect (no Privacy Mode)
- Parsec auto-reverts resolution on disconnect
- Shortest observed reconnect gap in live data: ~5 minutes
- 10 seconds absorbs sub-second network hiccups without delaying restore

### Host Disconnect Behavior: No Lock Screen

Without Privacy Mode (Teams/Warp subscription feature), Parsec does not lock the host screen on disconnect. The desktop remains accessible. The disconnect recipe can execute immediately after grace period without lock-screen interference.

Source: [Privacy Mode](https://support.parsec.app/hc/en-us/articles/32361381211284-Privacy-Mode)

### Connection Attempt Event: Omitted

The "trying to connect" log message only appears when connection approval is required (host must accept). With auto-connect enabled for the owner's devices, this event never fires. The `attempt` pattern is omitted from the default watcher config.

Source: [Hosting and Permissions](https://support.parsec.app/hc/en-us/articles/32381747079572-Hosting-and-Permissions)

### Watcher Command Surface

A new `Start-ParsecWatcher` exported function serves as the entry point. `Start-ParsecExecutor` remains available for manual recipe invocation but may be deprecated if the watcher fully subsumes its role. No compatibility shims — if superseded, it gets removed.

### Configuration Format: TOML

The watcher configuration uses TOML, consistent with recipe files. The PSToml module provides parsing. This supersedes ADR-7's JSON recommendation for the watcher's own configuration (recipe and executor state files may remain JSON where already implemented).

---

## References

- [auto-parsec — PowerShell Parsec automation](https://github.com/Borgotto/auto-parsec) — reference for log parsing patterns
- [MonitorSwapAutomation — Sunshine display switching](https://github.com/Nonary/MonitorSwapAutomation) — reference for grace period and event architecture
- [FileSystemWatcher best practices (powershell.one)](https://powershell.one/tricks/filesystem/filesystemwatcher)
- [Reusable File System Event Watcher (Microsoft DevBlogs)](https://devblogs.microsoft.com/powershell-community/a-reusable-file-system-event-watcher-for-powershell/)
- [Register-EngineEvent (Microsoft Learn)](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/register-engineevent?view=powershell-7.5)
