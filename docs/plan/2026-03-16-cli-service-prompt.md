# New PR Prompt: `pe.exe` CLI Binary and Windows Service

## Context

You are starting a new feature branch from `main` (after PR #3 merges) to build a C# CLI binary (`pe.exe`) that wraps the existing PowerShell module and registers the Parsec event watcher as a proper Windows Service.

Read these documents before starting:

- **ADR-11/12**: `docs/adr/2026-03-15-cli-and-service-architecture.md` — binding decisions for C# CLI and Windows Service
- **Handover plan**: `docs/plan/2026-03-15-cli-service-handover.md` — full context on what exists, what's missing, gaps, rationale, phase plan, complexity estimates, discovered issues, and the mode deprecation plan
- **Watcher ADR**: `docs/adr/2026-03-14-parsec-state-watcher.md` — ADR-8 through ADR-10 covering recipe username filter, log tailing, and Parsec resolution handling
- **CLAUDE.md**: `.claude/CLAUDE.md` — project conventions, testing mandate, research-first approach

## What exists

The PowerShell module `ParsecEventExecutor` is fully functional:

- `Start-ParsecWatcher` — long-running poll loop monitoring Parsec's `log.txt`, dispatching recipes on connect/disconnect events
- `Get-ParsecRecipe` / `Invoke-ParsecRecipe` — recipe loading and execution with dependency gating, verification, compensation
- `Save-ParsecSnapshot` / `Test-ParsecSnapshot` — display state capture and restore
- `Get-ParsecExecutorState` / `Repair-ParsecExecutorState` — state persistence and recovery
- `Invoke-ParsecConnectionProbe` — multi-layer connection validation (UDP, staleness, reboot)
- 117 tests passing, PSScriptAnalyzer clean

There is NO CLI, NO Windows Service, NO installer. Users must use PowerShell directly.

## Scope — what to build

### 1. Scaffold the C# CLI project

- Create `cli/` directory with `pe.csproj`, `Program.cs`, command structure
- Use `System.CommandLine` for argument parsing
- Use `System.Management.Automation` to load and invoke the PowerShell module
- Target .NET 8+ with single-file publish (`dotnet publish --self-contained -r win-x64`)

### 2. Implement CLI commands

```
pe service install    Register the watcher as a Windows Service
pe service uninstall  Remove the Windows Service
pe service start      Start the service (sc start)
pe service stop       Stop the service (sc stop)

pe recipe list        List all available recipes
pe recipe add         Scaffold a new recipe TOML file
pe recipe remove      Remove a recipe
pe recipe preview     Show what a recipe would do without executing

pe run <name>         Execute a recipe by name
pe run <name> --dry-run  Show execution plan without applying

pe restore            Restore the last persisted display state
pe restore list       List available restore points (snapshots)
pe restore --id <id>  Restore a specific snapshot
```

### 3. Implement the Windows Service

- Use `Microsoft.Extensions.Hosting.WindowsServices` with `UseWindowsService()`
- `pe service install` registers via `sc create`
- The service runs the watcher poll loop (ported from PowerShell to C#, or calling into PS module)
- Solve Session 0 constraint: the service runs in Session 0, but display APIs need the user's desktop session (Session 1+). Use `CreateProcessAsUser` to launch recipe execution in the user's session.

### 4. Remove DESKTOP/MOBILE mode concept

The binary mode state (`initial_mode`, `target_mode`, `desired_mode`, `actual_mode`) is legacy from the original two-state design. Remove it:

- Remove `initial_mode` and `target_mode` from recipe TOML schema
- Remove `desired_mode` and `actual_mode` from executor-state.json
- Replace mode-based recipe matching with event-type matching: connect recipes run on connect, disconnect recipes run on disconnect
- Recipes are paired by convention (e.g., `enter-mobile.toml` applies on connect, `return-desktop.toml` unrolls on disconnect) — not by mode labels

See the removal table in `docs/plan/2026-03-15-cli-service-handover.md`.

### 5. Package for distribution

- Single-file publish produces `pe.exe`
- Create a GitHub Release workflow
- Optional: WinGet manifest or Inno Setup installer

## Constraints

- The PowerShell module remains the authoritative implementation. The CLI is a thin wrapper.
- Research before implementing. Ground decisions in documentation and reference projects.
- Write tests. The project mandate requires live integration tests without mocks for system-level behavior.
- Do not modify existing recipe files or test fixtures without understanding their downstream dependencies.
- The Session 0 bridge (`CreateProcessAsUser`) is the highest-risk item. Research thoroughly before implementing. Fall back to Task Scheduler bridge if needed.

## Key decisions to make early

1. **Service account**: LocalSystem vs dedicated account
2. **Session bridge**: `CreateProcessAsUser` vs named pipe IPC vs Task Scheduler hybrid
3. **PS module location**: Bundled inside `pe.exe` resources vs external path reference
4. **`pe restore` semantics**: Define what "restore" means — last snapshot? specific run? full display reset?
5. **Config location**: `%ProgramData%\ParsecEventExecutor\` vs alongside `pe.exe`

## Out of scope

- New ingredients or display domain changes
- Parsec VDD integration
- Interactive first-connect profile assignment
- Config or recipe hot-reload (enhancement backlog)
