# Implementation Plan Status

## Current shipped surface

The shipped PowerShell module lives in `src/ParsecEventExecutor`.

Exported commands:

- `Invoke-ParsecRecipe`
- `Get-ParsecRecipe`
- `Get-ParsecIngredient`
- `Save-ParsecProfile`
- `Test-ParsecProfile`
- `Get-ParsecExecutorState`
- `Start-ParsecExecutor`

`Capture-ParsecProfile` is exported as an alias of `Save-ParsecProfile`.

The current architecture is a local recipe executor, not a live Parsec daemon. Recipes are TOML files parsed into ordered steps. Steps support dependency gating, optional verification, retries, basic conditions, and explicit compensation hooks.

Run results and local executor state are persisted as JSON under `%LOCALAPPDATA%\ParsecEventExecutor` in:

- `profiles/`
- `runs/`
- `logs/`
- `events/`

Implemented now:

- recipe parsing and execution
- ingredient registry and argument validation
- executor-state persistence and run-state persistence
- profile capture to JSON
- profile verification and approval gating
- built-in ingredient families for `display.*`, `profile.*`, `process.*`, `service.*`, and `command.invoke`
- manual event dispatch through `Start-ParsecExecutor`

`Start-ParsecExecutor` currently supports:

- `SwitchToMobile`
- `SwitchToDesktop`
- `VerifyOnly`
- `Reconcile`

## Deliberate placeholders and current limits

The repository recipes are placeholders only:

- `recipes/enter-mobile.toml`
- `recipes/return-desktop.toml`

Each recipe currently contains a single `profile.apply` step against `MOBILE` or `DESKTOP`.

Approval-gated placeholders are explicit in:

- `profiles/MOBILE.json`
- `profiles/DESKTOP.json`

Both profiles still carry `approved = false` and `approval_required` data, so they must be treated as scaffolding rather than finalized mode definitions.

Display mutation backends are not wired yet. The default adapter can observe screens through `System.Windows.Forms.Screen`, but these operations currently return `CapabilityUnavailable` until a concrete backend is implemented:

- `SetEnabled`
- `SetPrimary`
- `SetResolution`
- `SetOrientation`
- `SetScaling`

`process_actions`, `service_actions`, and `command_actions` are persisted in profile documents, but `profile.apply` does not execute them automatically. Any real process, service, or command behavior still needs explicit recipe steps using `process.*`, `service.*`, or `command.invoke`.

## Test status

Tests are written in Pester v5 style and currently cover:

- TOML recipe parsing
- dependency-gated executor behavior
- approval-gated placeholder recipes
- command invocation
- process start and compensation
- service ingredient contract behavior
- profile capture and verification

Run the suite with:

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -Command "& { Import-Module Pester -MinimumVersion 5.0 -Force; $config = New-PesterConfiguration; $config.Run.Path = 'tests'; Invoke-Pester -Configuration $config }"
```

Current result on March 11, 2026: 11 tests passed, 0 failed.

## Approval input required next

Concrete `MOBILE` and `DESKTOP` recipes must not be filled in until the following approval data is supplied:

- `active_monitors`
- `disabled_monitors`
- `primary_monitor`
- `resolution_per_monitor`
- `orientation_per_monitor`
- `refresh_rate_policy`
- `dpi_and_text_scaling`
- `process_actions`
- `service_actions`
- `command_actions`
- `unsupported_setting_policy`

Concrete `display.monitors` entries are also required for each approved monitor. Each entry must include:

- `device_name`
- `enabled`
- optional `is_primary`
- `bounds.width`
- `bounds.height`
- optional `orientation`
- optional `display.scaling.value`

`refresh_rate_policy` and `unsupported_setting_policy` are captured as required approval decisions, but they are not consumed by runtime code yet. `process_actions`, `service_actions`, and `command_actions` also still require recipe design work after approval.

## Immediate next step

Once the approval data is complete, replace the placeholder `profile.apply`-only recipes with explicit, ordered `MOBILE` and `DESKTOP` steps that match the approved monitor topology, scaling, orientation, and ancillary process or service actions.
