# Handover: CLI Binary and Windows Service

**Date**: 2026-03-15
**Status**: Not started — separate PR
**ADR**: [`2026-03-15-cli-and-service-architecture.md`](../adr/2026-03-15-cli-and-service-architecture.md)
**Prerequisites**: PR #3 (Parsec state watcher) merged

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
