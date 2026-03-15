# Architecture Decision Record: CLI Binary and Windows Service Architecture

**Date**: 2026-03-15
**Status**: Proposed — Deferred to separate PR
**Depends on**: Parsec state watcher (PR #3)

---

## Context

The Parsec Event Executor has a functional PowerShell module with a watcher daemon, recipe engine, and display management. However, it has no CLI entry point, no proper Windows Service registration, and no installer. Users must interact with the system via PowerShell commands directly. A production deployment needs:

1. A CLI binary (`pe.exe`) for user-facing commands
2. A Windows Service for the watcher daemon (not Task Scheduler)
3. Package and distribution mechanism

## ADR-11: CLI Binary in C#

### Decision

Build the CLI wrapper in C# using `System.CommandLine` for argument parsing and `System.Management.Automation` for PowerShell module invocation.

### Options Considered

| Option | Verdict | Reason |
|---|---|---|
| C# (.NET) | **Chosen** | Native PowerShell API access via `System.Management.Automation`, single-file publish, can host Windows Service via `Microsoft.Extensions.Hosting`, same ecosystem as the PS module |
| Rust | Rejected | Cannot call PowerShell directly — must shell out to `pwsh.exe`, two-language codebase, no shared state |
| C++ | Rejected | Excessive development overhead for a CLI tool, no ecosystem benefit |
| PowerShell script only | Rejected | No CLI UX, no service registration, requires PS knowledge to operate |

### CLI Shape

```
pe service start|stop|install|uninstall
pe recipe list|add|remove|duplicate|preview
pe run <recipe-name> [--dry-run]
pe restore [--id <uuid>] [list]
```

### Consequences

- The C# CLI project lives in `cli/` alongside the PowerShell module in `src/`
- The CLI loads the PowerShell module via `System.Management.Automation.PowerShell` — no shelling out
- Single-file publish via `dotnet publish --self-contained -r win-x64` produces `pe.exe`
- The PowerShell module remains the authoritative implementation; the CLI is a thin wrapper

---

## ADR-12: Windows Service via .NET Generic Host

### Decision

Replace the Task Scheduler daemon with a proper Windows Service using `Microsoft.Extensions.Hosting.WindowsServices`.

### Rationale

The current watcher runs as a `pwsh.exe` process launched by Task Scheduler at logon. This has limitations:

- No service management UI (`sc query`, `services.msc`)
- No clean start/stop semantics
- Brief window flash on startup
- Task Scheduler restart-on-failure is coarser than service recovery

A .NET Generic Host with `UseWindowsService()` provides:

- Proper SCM registration (`sc create`, `sc delete`)
- Clean start/stop/pause lifecycle
- No window flash (runs as background service)
- Native service recovery options
- Can run before user logon (with appropriate session handling)

### Session 0 Constraint

Display configuration APIs require the user's desktop session (Session 1+). The service runs in Session 0. The service must dispatch recipe execution to the user's session via one of:

1. `CreateProcessAsUser` — launch `pwsh.exe` in the user's session for recipe execution
2. Named pipe IPC — the service monitors logs and sends dispatch commands to a user-session helper process
3. Task Scheduler hybrid — the service creates on-demand tasks that run in the user's session

Option 1 is the most direct. The service monitors the Parsec log, and when a recipe needs to dispatch, it launches a short-lived `pwsh.exe -Command "Invoke-ParsecRecipe ..."` process in the logged-on user's session.

### Consequences

- `pe service install` registers the Windows Service
- `pe service start|stop` maps to `sc start|stop`
- `pe service uninstall` removes the service
- The watcher poll loop moves from PowerShell to C# (calling into the PS module for recipe dispatch)
- The PowerShell `Start-ParsecWatcher` remains available for development/debugging but is not the production entry point

---

## References

- [System.CommandLine (Microsoft)](https://learn.microsoft.com/en-us/dotnet/standard/commandline/)
- [.NET Generic Host Windows Service](https://learn.microsoft.com/en-us/dotnet/core/extensions/windows-service)
- [System.Management.Automation (PowerShell SDK)](https://learn.microsoft.com/en-us/dotnet/api/system.management.automation)
- [Single-file deployment (dotnet publish)](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file)
- [CreateProcessAsUser (Win32 API)](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessasusera)
