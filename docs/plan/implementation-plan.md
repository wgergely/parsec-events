# Implementation Status

## Topic

Recipe-authored mobile preset execution with transient desktop snapshot restore.

## Current Architecture

The live implementation is recipe-first and snapshot-driven.

Authored configuration:

- TOML recipe files in `recipes/`

Machine-written runtime state:

- JSON under `%LOCALAPPDATA%\ParsecEventExecutor`
- `snapshots/`
- `runs/`
- `logs/`
- `events/`
- `executor-state.json`

The repository no longer treats `DESKTOP` or `MOBILE` as authored JSON profile files. The normal desktop state is captured at runtime as a transient snapshot before the mobile recipe runs, then restored from that snapshot on disconnect.

## Current Command Surface

The PowerShell module in `src/ParsecEventExecutor` currently exports:

- `Invoke-ParsecRecipe`
- `Get-ParsecRecipe`
- `Get-ParsecIngredient`
- `Save-ParsecSnapshot`
- `Test-ParsecSnapshot`
- `Save-ParsecProfile`
- `Test-ParsecProfile`
- `Get-ParsecExecutorState`
- `Start-ParsecExecutor`

Aliases:

- `Capture-ParsecSnapshot`
- `Capture-ParsecProfile`

`Save-ParsecProfile` and `Test-ParsecProfile` remain compatibility shims over snapshot behavior. The canonical surface is snapshot-oriented, not profile-file-oriented.

## Recipe and Ingredient Model

Recipes are declarative TOML documents parsed into ordered steps.

Each step now dispatches:

- `ingredient`
- `operation`
- `arguments`
- `depends_on`
- `verify`
- retry settings
- compensation policy

The ingredient contract is operation-based in `src/ParsecEventExecutor/Private/Ingredients.ps1`. Ingredients declare manifests with capabilities and supported operations such as:

- `apply`
- `capture`
- `reset`
- `verify`

Built-in ingredient families currently cover:

- `display.*`
- `process.*`
- `service.*`
- `command.invoke`

## Mission Recipe Behavior

`recipes/enter-mobile.toml` currently does one verified thing:

- capture `desktop-pre-parsec` through `display.snapshot` using the `capture` operation

`recipes/return-desktop.toml` currently does one verified thing:

- restore `desktop-pre-parsec` through `display.snapshot` using the `reset` operation

This means the executor now models the correct mission flow:

1. Capture the live desktop state before the Parsec/mobile transition.
2. Apply mobile-oriented ingredient steps when they are authored into the mobile recipe.
3. Restore the captured desktop snapshot on return.

## Verified Runtime Behavior

Implemented and verified now:

- TOML recipe parsing
- dependency-gated step execution
- operation-based ingredient dispatch
- transient snapshot capture
- transient snapshot restore
- executor-state and run-state persistence
- manual event routing through `Start-ParsecExecutor`

Verification status on March 11, 2026:

- `Invoke-Pester` passes `14` tests
- `Invoke-ScriptAnalyzer` passes with `PSScriptAnalyzerSettings.psd1`

Run verification with:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -Command "Invoke-Pester -Path 'tests' -Output Detailed"
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -Command "Invoke-ScriptAnalyzer -Path 'Y:\code\parsec-events-worktrees\main' -Recurse -Settings 'Y:\code\parsec-events-worktrees\main\PSScriptAnalyzerSettings.psd1'"
```

## Remaining Gaps

Not implemented yet:

- real display mutation through a `DisplayConfig` backend
- concrete mobile display/process/service/command steps in `recipes/enter-mobile.toml`
- daemon hosting beyond the manual entrypoint
- Parsec log tailing and event ingestion

The default mobile recipe is still a safe scaffold. It captures the transient desktop snapshot but does not yet encode the actual mobile monitor, orientation, scaling, process, or service actions.
