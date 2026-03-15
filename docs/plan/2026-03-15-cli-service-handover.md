# Handover: CLI Binary and Windows Service

**Date**: 2026-03-15
**Status**: Not started — separate PR
**ADR**: [`2026-03-15-cli-and-service-architecture.md`](../adr/2026-03-15-cli-and-service-architecture.md)
**Prerequisites**: PR #3 (Parsec state watcher) merged

---

## Current State and Gaps

### What we built

PR #3 implements a **long-running PowerShell script** (`Start-ParsecWatcher`) that blocks in a poll loop monitoring Parsec's log file. It behaves like a daemon — it runs indefinitely, detects events, and dispatches recipes — but it is just a `while` loop inside a `pwsh.exe` process. There is no Windows Service, no Service Control Manager registration, and no `sc.exe` integration.

Installation is via `Register-ParsecWatcherTask`, which creates a Task Scheduler entry triggered at user logon. The user must run `Import-Module ParsecEventExecutor; Register-ParsecWatcherTask` manually in PowerShell.

### Daemon vs Service — they are not the same thing

A **daemon** is any long-running background process. Our watcher is a daemon in this sense.

A **Windows Service** is a specific Windows construct: it registers with the Service Control Manager (SCM), runs in Session 0 (isolated from the desktop), has start/stop/pause lifecycle semantics managed by `services.msc` and `sc.exe`, and survives user logoff. Our watcher is NOT a Windows Service.

Our current approach is the same as auto-parsec: a PowerShell script launched by Task Scheduler at logon. This works but has limitations:

- No `services.msc` visibility or control
- Brief window flash on startup (PowerShell console)
- Task Scheduler restart-on-failure is coarser than service recovery
- No clean stop semantics without killing the process
- Only runs while the user is logged in

### What's missing for production

| Gap | Impact |
|---|---|
| No CLI entry point | Users must know PowerShell to operate the system |
| No installer or package | Manual setup only |
| No service management UI | Cannot query status, start/stop, or configure without PS commands |
| No way to view logs or manage recipes | Requires navigating `%LOCALAPPDATA%\ParsecEventExecutor\` manually |
| No proper Windows Service | No SCM integration, no logoff survival, no `sc.exe` control |

### Why C# for the CLI

The PowerShell module runs on .NET. A C# CLI binary can:

- Load and invoke the PowerShell module directly via `System.Management.Automation` — no shelling out to `pwsh.exe`
- Share types and state with the PowerShell backend
- Register as a proper Windows Service via `Microsoft.Extensions.Hosting.WindowsServices`
- Package as a single-file `.exe` with `dotnet publish --self-contained`
- Use `System.CommandLine` for the CLI argument parsing

Alternatives considered:

| Language | Verdict | Reason |
|---|---|---|
| C# (.NET) | **Chosen** | Native PS API access, single ecosystem, can host Windows Service, single-file publish |
| Rust | Rejected | Cannot call PowerShell directly — must shell out to `pwsh.exe`, two-language codebase |
| C++ | Rejected | Massive development overhead for a CLI, no benefit over Rust |
| PowerShell script only | Rejected | No CLI UX, no service registration, requires PS knowledge |

---

## Scope

Build a C# CLI binary (`pe.exe`) that wraps the PowerShell module and registers the watcher as a proper Windows Service.

## What Exists (from PR #3)

| Component | Status | Entry Point |
|---|---|---|
| Watcher daemon | Functional | `Start-ParsecWatcher` (PowerShell, blocks in poll loop) |
| Task Scheduler registration | Functional | `Register-ParsecWatcherTask` (at-logon trigger) |
| Recipe engine | Functional | `Invoke-ParsecRecipe`, `Get-ParsecRecipe` |
| State persistence | Functional | `Get-ParsecExecutorState`, `Repair-ParsecExecutorState` |
| Snapshot management | Functional | `Save-ParsecSnapshot`, `Test-ParsecSnapshot` |
| Connection probe | Functional | `Invoke-ParsecConnectionProbe` (internal) |

## What Needs Building

### Phase 1: C# CLI Scaffold

```
cli/
├── pe.csproj
├── Program.cs
├── Commands/
│   ├── ServiceCommand.cs      # pe service start|stop|install|uninstall
│   ├── RecipeCommand.cs       # pe recipe list|add|remove|duplicate|preview
│   ├── RunCommand.cs          # pe run <name> [--dry-run]
│   └── RestoreCommand.cs      # pe restore [--id <uuid>] [list]
├── Services/
│   ├── PowerShellHost.cs      # Loads and invokes the PS module
│   └── WatcherService.cs      # IHostedService for Windows Service
└── appsettings.json
```

**Dependencies:**
- `System.CommandLine` — CLI parsing
- `System.Management.Automation` — PowerShell invocation
- `Microsoft.Extensions.Hosting.WindowsServices` — service host

### Phase 2: Command Implementation

#### `pe service install`
- Copies `pe.exe` to a stable location (e.g., `%ProgramFiles%\ParsecEventExecutor\`)
- Registers Windows Service via `sc create ParsecEventWatcher binPath= "...pe.exe service run"`
- Sets recovery options (restart on failure)
- Sets service account (LocalSystem or configurable)

#### `pe service start|stop`
- Maps to `sc start ParsecEventWatcher` / `sc stop ParsecEventWatcher`

#### `pe service run` (internal — called by SCM)
- Starts the .NET Generic Host with `UseWindowsService()`
- The hosted service loads the PowerShell module and runs the watcher poll loop
- On recipe dispatch: launches `pwsh.exe` in the user's session via `CreateProcessAsUser`

#### `pe recipe list`
- Invokes `Get-ParsecRecipe` via the PowerShell host
- Formats output as a table

#### `pe run <name> [--dry-run]`
- Invokes `Invoke-ParsecRecipe -NameOrPath <name>` or `Start-ParsecExecutor`
- Streams step results to stdout

#### `pe restore`
- Needs research: determine what "restore" means in context
- Candidates: restore last snapshot, restore specific run state, restore display config
- `pe restore list` — show available restore points (snapshots + run history)
- `pe restore --id <uuid>` — restore a specific snapshot

### Phase 3: Session 0 Bridge

The service runs in Session 0 (no desktop access). Recipe execution needs the user's session. Options:

1. **`CreateProcessAsUser`** — the service launches `pwsh.exe -Command "Invoke-ParsecRecipe ..."` in the user's desktop session. Requires `SE_ASSIGNPRIMARYTOKEN_NAME` privilege (LocalSystem has this).

2. **Named pipe IPC** — the service sends dispatch commands to a small user-session helper (`pe agent`) that runs at logon and executes recipes.

3. **Task Scheduler bridge** — the service creates a one-shot scheduled task that runs in the user's session. Clunky but works without elevated privileges.

**Recommended: Option 1** for simplicity. Fall back to Option 3 if `CreateProcessAsUser` proves unreliable.

### Phase 4: Packaging

- `dotnet publish -c Release -r win-x64 --self-contained -p:PublishSingleFile=true`
- Produces a single `pe.exe` (~60MB with .NET runtime)
- Distribution: GitHub Release asset or WinGet manifest
- Installer (optional): Inno Setup or WiX for guided install

---

## Key Decisions to Make Before Starting

1. **Service account**: LocalSystem (full privileges) vs a dedicated service account?
2. **Session bridge**: `CreateProcessAsUser` vs named pipe helper?
3. **PS module location**: Bundled inside `pe.exe` resources vs external path?
4. **`pe restore` semantics**: What exactly should be restorable?
5. **Config location**: `%ProgramData%\ParsecEventExecutor\` vs alongside `pe.exe`?

---

## Estimated Complexity

| Phase | Effort | Risk |
|---|---|---|
| CLI scaffold + `pe recipe list` + `pe run` | Low | Low — straightforward PS invocation |
| `pe service install|start|stop` | Medium | Medium — SCM registration, recovery config |
| `pe service run` (hosted service) | Medium | Low — .NET Generic Host is well-documented |
| Session 0 bridge | High | High — `CreateProcessAsUser` is complex Win32 interop |
| Packaging + distribution | Low | Low — `dotnet publish` handles most of it |

## References

- [winsw](https://github.com/winsw/winsw) — alternative to native service registration (used by ParsecVDA-Always-Connected)
- [TopShelf](https://topshelf.readthedocs.io/) — alternative .NET service host (simpler than Generic Host)
- [Spectre.Console](https://spectreconsole.net/) — rich console output for CLI (alternative to System.CommandLine)
