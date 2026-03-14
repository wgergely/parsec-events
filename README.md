# Parsec Event Executor

This repository contains a PowerShell 7 recipe executor for Parsec-driven desktop/mobile transitions.

## Current Model

- Authored configuration is TOML in `recipes/`
- Runtime state is machine-written JSON under `%LOCALAPPDATA%\ParsecEventExecutor`
- The desktop state is not a repo-tracked profile file
- The desktop state is captured transiently before the mobile recipe runs and restored on return

The executor is now recipe-first, not profile-file-driven.

## Current Behavior

`recipes/enter-mobile.toml` currently captures a transient `desktop-pre-parsec` snapshot.

`recipes/return-desktop.toml` restores that snapshot.

The ingredient system is operation-based. Ingredients expose capabilities such as:

- `apply`
- `capture`
- `reset`
- `verify`

Built-in ingredients currently cover display, process, service, command, NVIDIA, personalization, snapshot, and window execution surfaces.

All built-in ingredient manifests now declare their owning `domain`, and recipe execution now validates `depends_on` as a DAG before running steps.

## Exported Commands

- `Invoke-ParsecRecipe`
- `Get-ParsecRecipe`
- `Get-ParsecIngredient`
- `Save-ParsecSnapshot`
- `Test-ParsecSnapshot`
- `Save-ParsecProfile`
- `Test-ParsecProfile`
- `Get-ParsecExecutorState`
- `Start-ParsecExecutor`

## Verification

Current verification status on March 14, 2026:

- targeted migration suites are green:
  - `tests/StandaloneIngredient.Tests.ps1`
  - `tests/Executor.Tests.ps1`
- the full `tests/` suite still has adjacent failures under active triage

Run them with:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -Command "Invoke-Pester -Path 'tests' -Output Detailed"
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -Command "Invoke-ScriptAnalyzer -Path 'Y:\code\parsec-events-worktrees\main' -Recurse -Settings 'Y:\code\parsec-events-worktrees\main\PSScriptAnalyzerSettings.psd1'"
```

## Remaining Work

- complete live validation for topology-changing and scaling-changing restore paths
- reduce display-domain complexity through internal decomposition
- finish triaging the remaining non-targeted failing test surfaces
- add daemon hosting and later Parsec log ingestion

The implementation detail summary is in `docs/plan/implementation-plan.md`.
