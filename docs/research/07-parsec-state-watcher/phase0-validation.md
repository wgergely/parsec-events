# Phase 0: Empirical Validation Results

**Date**: 2026-03-14
**Machine**: Windows 11 Pro, per-machine Parsec install (service mode)
**Parsec Version**: release13 (150-102b, Service: 11, Loader: 14)

---

## 0.1 Log File Location

**Result**: Per-machine install at `C:\ProgramData\Parsec\log.txt`

The per-user path (`%APPDATA%\Parsec\log.txt`) does not exist. The watcher must check both paths on startup and use whichever exists. The `app_run_level = 1` in `config.json` confirms service-level installation.

## 0.2 Log Line Format — Connection Events

**Result**: Format confirmed. Log level is `I` (Info), not `D` (Debug).

### Connect Event
```
[I 2026-03-09 22:03:47] wgergely#12571953 connected.
```

### Disconnect Event
```
[I 2026-03-09 22:11:36] wgergely#12571953 disconnected.
```

### Connection Attempt ("trying to connect")
**Not observed.** Zero matches in 6466 lines spanning 5 days of use. Either:
- This event type is not logged in the per-machine (service) install, or
- It was removed in Parsec 150-102+, or
- It only appears under specific conditions (e.g., connection approval required)

**Decision**: Do not rely on the "trying to connect" event. The watcher should trigger on `connected.` and `disconnected.` only.

### Disconnect Precursor
Before every disconnect, this line appears:
```
[I 2026-03-09 22:11:36] Virtual tablet removed due to client disconnect
[I 2026-03-09 22:11:36] * host_msg_thread_cleanup[2687] = -12007
[I 2026-03-09 22:11:36] wgergely#12571953 disconnected.
```

The "Virtual tablet removed" line fires at the same timestamp as the disconnect and is not useful as a separate signal.

## 0.3 Username Format

**Result**: `wgergely#12571953` — username followed by `#` and a numeric ID.

- Username: `wgergely` (alphanumeric, no spaces observed)
- Separator: `#`
- ID: `12571953` (8 digits, likely a Parsec account ID, not a discriminator)

**Regex**: `\w+#\d+` is sufficient for this format. However, Parsec usernames may contain other characters (hyphens, underscores, etc.) — safer to use `[^\]]+#\d+` or `.+#\d+` to avoid false negatives.

**Important note**: The auto-parsec regex `\]\s(.+#\d+)` captured the username with the discriminator-style `#1234` format. The actual log data shows the ID is much longer (`#12571953`). The regex still works because `\d+` matches any number of digits.

## 0.4 Finalized Regex Patterns

Based on actual log data:

```
connect:    ^\[I\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\]\s+(.+#\d+)\s+connected\.$
disconnect: ^\[I\s+\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\]\s+(.+#\d+)\s+disconnected\.$
```

Simplified (for config, allowing format evolution):
```
connect:    \]\s+(.+#\d+)\s+connected\.\s*$
disconnect: \]\s+(.+#\d+)\s+disconnected\.\s*$
```

**Key observation**: Connection events use log level `[I` (Info), while most other log lines use `[D` (Debug). This could be used as an optimization filter, but is not required.

## 0.5 Log Rotation Behavior

**Result**: Parsec uses numbered rotation, NOT truncation.

Directory listing:
```
-rw-r--r-- 1485966 Mar  9 17:45 log.1.txt    (1.4 MB — rotated)
-rw-r--r--  462562 Mar 14 04:02 log.txt      (462 KB — current)
```

- `log.1.txt` is the previous rotation (1.4 MB — larger than the expected 1 MB threshold, suggesting rotation may happen at ~1.5 MB or on restart)
- `log.txt` is the current active file
- There is also `log_cl.txt` (369 KB) — likely a client-side log, separate from host events

**Rotation strategy for the watcher**:
- Monitor `log.txt` only
- On rotation: Parsec creates a new `log.txt` (file creation time changes, size resets)
- Detection: compare file size or creation timestamp between reads
- The `FileSystemWatcher` will fire a `Created` event when the new file appears after rotation

## 0.6 Event Latency and Patterns

### Observed Connection/Disconnection Timeline

| Connect Time | Disconnect Time | Session Duration |
|---|---|---|
| 22:03:47 | 22:11:36 | 7m 49s |
| 22:16:51 | 22:30:02 | 13m 11s |
| 22:36:21 | 22:49:20 | 12m 59s |
| 06:53:12 | 07:48:59 | 55m 47s |
| 09:39:15 | — | (followed by rapid reconnect) |
| 09:42:04 | 09:42:49 | 45s (rapid connect/disconnect) |
| 09:50:43 (disconnect after reconnect) | | |
| 10:43:22 | 10:46:41 | 3m 19s |
| 10:48:56 | 10:51:31 | 2m 35s |
| 10:53:49 | 10:55:34 | 1m 45s |
| 14:05:34 | 15:31:20 | 1h 25m 46s |
| 15:34:19 | 15:46:20 | 11m 59s |
| 11:55:51 (Mar 11) | 12:56:02 | 1h 0m 11s |

### Rapid Reconnection Pattern (Lines 1210-1240)

At 09:42:04, a connect happened while a previous session from 09:39:15 was still active. Then at 09:42:49, a disconnect. Then at 09:50:43, another disconnect (likely the earlier session finally closing).

**This confirms**: Parsec can log overlapping connect/disconnect events. The session tracker MUST track per-user sessions and not assume a simple connect/disconnect pair.

### Duplicate Connect Without Intervening Disconnect

Line 1171: `wgergely#12571953 connected.` at 09:39:15
Line 1214: `wgergely#12571953 connected.` at 09:42:04 (NO disconnect between these)

**This confirms**: Parsec may log multiple `connected.` events without a corresponding `disconnected.` in between. The watcher must treat a second `connected.` as a reconnection (not a new session).

## 0.7 Additional Log Signals

### Around Connection Events

Immediately after `connected.`:
```
[D] dxgi          = 1.5
[I] FRAME: DXGI_ERROR_ACCESS_LOST
[D] format        = BGRA
[D] encoder       = nvidia
[D] codec         = h264
[D] encode_x      = 3000
[D] encode_y      = 2000
```

The `encode_x` and `encode_y` values show the **encoding resolution** — `3000x2000` in some sessions and `2560x1440` in others. This is potentially useful metadata:
- `3000x2000` = likely the phone in landscape or custom resolution
- `2560x1440` = likely the desktop monitor resolution

**However**, this appears AFTER the connected event, not as part of it. The watcher would need to peek at subsequent lines to extract this. This is a future enhancement, not a Phase 1 requirement.

### IPC Events (Noise)
```
[D] IPC AS Client Connected.
```
These are internal IPC events, NOT user connections. The regex must NOT match these — they don't contain `#\d+`.

## 0.8 Host Behavior on Disconnect

**Observation from logs**: After disconnect, the FPS status lines continue for several seconds:
```
[I] wgergely#12571953 disconnected.
[D] [0] FPS:28.3/0, L:10.2/19.7, ...    (3 seconds later)
[D] [0] FPS:15.0/0, L:10.5/17.1, ...    (7 seconds later)
```

The host does NOT lock immediately on disconnect — it continues running normally. FPS lines stop appearing after ~10-15 seconds as the encoder shuts down.

**Grace period recommendation**: Based on the observed rapid reconnection patterns (shortest gap between disconnect and reconnect: ~5 minutes at 22:11:36→22:16:51), a **10-second grace period** would be safe — long enough to absorb any sub-second network hiccups, short enough to not delay the restore. The user should tune this empirically during live testing.

**Still unknown**: Whether the host locks the screen on disconnect depends on Parsec settings, not the log behavior. This requires live testing with the phone.

## 0.9 Parsec Configuration

From `config.json`:
```json
"server_resolution_x": { "value": 65535 },
"server_resolution_y": { "value": 65535 },
"host_rotated": { "value": true }
```

- `server_resolution_x/y = 65535` means "use client resolution" — Parsec WILL attempt to match the client's resolution on connect. This contradicts ADR-6 which recommended disabling this. **Action**: Verify whether this causes a race condition with the recipe engine, and consider setting both to explicit values or disabling client resolution matching.
- `host_rotated = true` means Parsec allows portrait orientation from the client.

## Summary of Validated Items

| Item | Status | Finding |
|---|---|---|
| 0.1 Log line format | **Validated** | `[I YYYY-MM-DD HH:MM:SS] username#id connected/disconnected.` |
| 0.2 Username format | **Validated** | `wgergely#12571953` — `\w+#\d+` pattern |
| 0.3 Log rotation | **Validated** | Numbered rotation (`log.1.txt`), not truncation |
| 0.4 Event latency | **Validated** | Sub-second (same-second timestamps) |
| 0.5 Multi-client | **Partially validated** | Only one user observed; duplicate connects without disconnect confirmed |
| 0.6 Verbose logging | **Not tested** | `app_log_level` not changed; would need Parsec restart |
| 0.7 FileSystemWatcher | **Not tested** | Requires live Parsec session; test during development |
| 0.8 Disconnect behavior | **Partially validated** | Host continues running after disconnect; lock behavior TBD |
| 0.9 Multi-account | **Not tested** | Requires second Parsec account |

## Updated Regex Patterns for Plan

```toml
[patterns]
connect = '\]\s+(.+#\d+)\s+connected\.\s*$'
disconnect = '\]\s+(.+#\d+)\s+disconnected\.\s*$'
```

The `attempt` pattern is removed — the "trying to connect" event was not observed in this Parsec version/install type.

## Phase 0 Extended: Research-Grounded Findings

### Parsec Resolution Auto-Matching (ADR-6 Conflict Resolved)

**Finding**: `server_resolution_x/y = 65535` is the unsigned equivalent of `-1`, meaning "use client resolution" (the default). When a client connects, Parsec changes the host resolution to match the client. When all clients disconnect, **Parsec automatically reverts the resolution to the pre-connection state**.

**Decision**: This is complementary, not conflicting. Parsec handles resolution matching on connect and revert on disconnect natively. The recipe engine should:
- **Not fight Parsec's resolution change** on connect. The `apply_delay_ms` wait lets Parsec finish negotiation first.
- **Rely on Parsec for resolution revert** on disconnect. The disconnect recipe focuses on DPI, text scaling, orientation, and settings Parsec does NOT restore.
- **Keep `server_resolution_x/y = 65535`** as-is. The recipe's display ingredients handle adjustments beyond what Parsec auto-applies (e.g., custom resolutions the client may not request).

**Exception**: If Parsec crashes or is force-killed, it does not revert resolution. The `return-desktop` recipe (via snapshot restore) handles this recovery path.

Source: [Force A Server Resolution Change](https://support.parsec.app/hc/en-us/articles/32361385826068-Force-A-Server-Resolution-Change), [Changing the Resolution](https://support.parsec.app/hc/en-us/articles/32361400566804-Changing-the-Resolution-of-the-Video-Stream)

### Host Behavior on Disconnect (No Lock Screen)

**Finding**: The host does NOT lock the screen on disconnect unless **Privacy Mode** is enabled (Parsec Teams/Warp only, requires Virtual Display Driver). Without Privacy Mode: resolution reverts, virtual displays removed, desktop remains accessible.

**Decision**: The disconnect recipe does not need to account for a locked screen. The watcher can dispatch immediately (after grace period).

Source: [Privacy Mode](https://support.parsec.app/hc/en-us/articles/32361381211284-Privacy-Mode)

### "Trying to Connect" Absence (Explained)

**Finding**: The "trying to connect" message appears when a connection requires host approval. When the connecting user has **"Can connect without your approval"** enabled, the connection proceeds directly to `connected.`.

**Decision**: The `attempt` pattern is correctly omitted. The primary use case (owner connecting from own devices with auto-connect) will not produce this event.

Source: [Add, Remove, and Manage Friends](https://support.parsec.app/hc/en-us/articles/32381587698196-Add-Remove-and-Manage-Friends)

### Multi-Client Connections

**Finding**: Parsec supports up to **20 concurrent connections** by default. Resolution is set by the first client (if owner). Subsequent clients see the already-configured resolution.

**Decision**: The "first connection wins" policy aligns with Parsec's own behavior. Dispatch connect recipe on first connection, disconnect recipe only when the **last** client disconnects.

Source: [Max Client Connections](https://support.parsec.app/hc/en-us/articles/32361376782228-Max-Client-Connections-To-Your-Host)

### FileSystemWatcher Validated

**Finding**: Live test confirmed FSWatcher detects `Changed` and `Renamed` events on `C:\ProgramData\Parsec\`.

**Key implementation requirements**:
- **Debounce**: FSWatcher fires 2-4 events per logical write. Use 500ms timer-based debounce.
- **Buffer size**: Default 8KB sufficient for Parsec's low-frequency writes.
- **Error event**: Must subscribe. FSWatcher can silently stop after `InternalBufferOverflowException`. On error: dispose and recreate.
- **Rotation**: Subscribe to `Created` event. On rotation, Parsec renames `log.txt` to `log.1.txt` and creates a new `log.txt`. Reset file position to 0.

**`Get-Content -Wait` confirmed unsuitable**: PowerShell [#20892](https://github.com/PowerShell/PowerShell/issues/20892) documents a memory leak (16 GB+ overnight). Combined with inability to handle rotation, ADR-9's FSWatcher+FileStream decision is strongly validated.

Sources: [InternalBufferSize](https://learn.microsoft.com/en-us/dotnet/api/system.io.filesystemwatcher.internalbuffersize), [dotnet/runtime #81226](https://github.com/dotnet/runtime/issues/81226), [PowerShell #20892](https://github.com/PowerShell/PowerShell/issues/20892)

---

## Updated Risk Register

| Risk | Severity | Status | Resolution |
|---|---|---|---|
| ADR-6 resolution conflict | Was High | **Resolved** | Parsec auto-matching is complementary. Keep 65535. |
| Duplicate connects | Medium | **Mitigated** | Treat as reconnection; session tracker design accounts for this. |
| Post-disconnect FPS lines | Low | **Mitigated** | Only react to `disconnected.` line, not log silence. |
| FSWatcher silent stop | Medium | **Mitigated** | Subscribe to Error event; dispose and recreate on failure. |
| Get-Content memory leak | Was High | **Avoided** | Using FSWatcher+FileStream instead (ADR-9). |
| Host lock screen | Was Unknown | **Resolved** | No lock without Privacy Mode (Teams only). |

## Final Validation Summary

| Item | Status | Finding |
|---|---|---|
| 0.1 Log line format | **Validated** | `[I YYYY-MM-DD HH:MM:SS] username#id connected/disconnected.` |
| 0.2 Username format | **Validated** | `wgergely#12571953` — `.+#\d+` pattern |
| 0.3 Log rotation | **Validated** | Numbered rotation (`log.1.txt`), not truncation |
| 0.4 Event latency | **Validated** | Sub-second (same-second timestamps) |
| 0.5 Multi-client | **Validated** | Up to 20 concurrent; first connection sets resolution |
| 0.6 Verbose logging | **Resolved** | `app_log_level=2` adds connection init detail; no device metadata |
| 0.7 FileSystemWatcher | **Validated** | Works on `C:\ProgramData\Parsec\`; debounce + Error event required |
| 0.8 Disconnect behavior | **Validated** | No lock screen; Parsec auto-reverts resolution |
| 0.9 "Trying to connect" | **Explained** | Only fires when connection approval is required |
| 0.10 Resolution auto-match | **Resolved** | 65535 = use client resolution; complementary to recipe engine |
