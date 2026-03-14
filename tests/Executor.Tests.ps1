$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

Describe 'Invoke-ParsecRecipe' {
    InModuleScope ParsecEventExecutor {
        It 'preserves drift in the sequence terminal status summary' {
            $runRecord = @{
                step_results = @(
                    @{ status = 'SucceededWithDrift' }
                )
            }

            Resolve-ParsecRecipeSequenceTerminalStatus -RunRecord $runRecord | Should -Be 'SucceededWithDrift'
        }

        It 'does not attempt compensation reset when the ingredient lacks reset support' {
            $step = @{
                id = 'run-command'
                ingredient = 'command.invoke'
                operation = 'apply'
                depends_on = @()
                arguments = @{ file_path = 'echo'; arguments = @('hello') }
                verify = $true
                compensation_policy = 'explicit'
                retry_count = 0
                retry_delay_ms = 0
                allow_diagnostics = $false
                condition = @{}
            }
            $runRecord = @{
                step_results = @()
                compensation_logs = @()
            }

            Mock Invoke-ParsecIngredientCommandInternal {
                [ordered]@{
                    ingredient_name = 'command.invoke'
                    status = 'Failed'
                    token_id = $null
                    token_path = $null
                    capture_result = $null
                    operation_result = @{ Status = 'Failed'; Message = 'Command failed.' }
                    readiness_result = $null
                    verify_result = $null
                    reset_result = $null
                    invocation_id = 'apply-invocation'
                    started_at = '2026-03-12T00:00:00.0000000+00:00'
                    completed_at = '2026-03-12T00:00:01.0000000+00:00'
                    message = 'Command failed.'
                }
            } -ParameterFilter { $Name -eq 'command.invoke' -and $Operation -eq 'apply' }

            $result = Invoke-ParsecRecipeSequenceStep -Step $step -RunRecord $runRecord -StateRoot $TestDrive

            $result.status | Should -Be 'Failed'
            $result.message | Should -Be 'Command failed.'
            $result.compensation_result | Should -BeNullOrEmpty
            Should -Invoke Invoke-ParsecIngredientCommandInternal -Times 1 -Exactly -ParameterFilter { $Name -eq 'command.invoke' -and $Operation -eq 'apply' }
            Should -Invoke Invoke-ParsecIngredientCommandInternal -Times 0 -Exactly -ParameterFilter { $Name -eq 'command.invoke' -and $Operation -eq 'reset' }
        }
    }

    InModuleScope ParsecEventExecutor {
        BeforeEach {
            . (Join-Path $PSScriptRoot 'IngredientTestSupport.ps1')
            Initialize-ParsecIngredientTestEnvironment
        }

        It 'persists executor state and run history when invoking a recipe directly' {
            $stateRoot = Join-Path $TestDrive 'state-success'
            $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\resolution-sequence.toml'

            $result = Invoke-ParsecRecipe -NameOrPath $recipePath -StateRoot $stateRoot -Confirm:$false

            $result.terminal_status | Should -Be 'Succeeded'
            $result.step_results[0].status | Should -Be 'Succeeded'
            $result.transition_id | Should -Not -BeNullOrEmpty
            (Test-Path (Join-Path $stateRoot 'executor-state.json')) | Should -BeTrue
            (Test-Path (Join-Path $stateRoot "runs\$($result.run_id).json")) | Should -BeTrue
            (Get-ChildItem -Path (Join-Path $stateRoot 'events') -File).Count | Should -BeGreaterThan 0
        }

        It 'blocks dependent steps after a failure on the executor-backed recipe path' {
            $stateRoot = Join-Path $TestDrive 'state-failure'
            $recipePath = Join-Path $TestDrive 'failure-blocks-resolution.toml'
            @"
name = "failure-blocks-resolution"
description = "Dependency-gated failure using the display resolution ingredient."

[[steps]]
id = "failing-resolution"
ingredient = "set-resolution"
verify = true
retry_count = 0
retry_delay_ms = 0

[steps.arguments]
width = 1600
height = 900

[[steps]]
id = "blocked-resolution"
ingredient = "set-resolution"
depends_on = ["failing-resolution"]
verify = true
retry_count = 0
retry_delay_ms = 0

[steps.arguments]
width = 1280
height = 720
"@ | Set-Content -LiteralPath $recipePath -Encoding UTF8

            $result = Invoke-ParsecRecipe -NameOrPath $recipePath -StateRoot $stateRoot -Confirm:$false

            $result.terminal_status | Should -Be 'Failed'
            $result.step_results[0].status | Should -Be 'Failed'
            $result.step_results[1].status | Should -Be 'Blocked'
        }

        It 'rejects recipe graphs with dependency cycles before execution starts' {
            $stateRoot = Join-Path $TestDrive 'cycle-validation'
            $recipePath = Join-Path $TestDrive 'cycle-validation.toml'
            @"
name = "cycle-validation"

[[steps]]
id = "alpha"
ingredient = "set-resolution"
depends_on = ["beta"]

[steps.arguments]
width = 1280
height = 720

[[steps]]
id = "beta"
ingredient = "set-resolution"
depends_on = ["alpha"]

[steps.arguments]
width = 1920
height = 1080
"@ | Set-Content -LiteralPath $recipePath -Encoding UTF8

            $result = Invoke-ParsecRecipe -NameOrPath $recipePath -StateRoot $stateRoot -Confirm:$false

            $result.terminal_status | Should -Be 'Failed'
            @($result.validation_errors).Count | Should -Be 1
            $result.validation_errors[0] | Should -Match 'dependency cycle'
            @($result.step_results).Count | Should -Be 0
            $script:IngredientObservedState.monitors[0].bounds.width | Should -Be 1920
        }

        It 'schedules ready steps in deterministic topological order' {
            $stateRoot = Join-Path $TestDrive 'topological-order'
            $recipePath = Join-Path $TestDrive 'topological-order.toml'
            @"
name = "topological-order"

[[steps]]
id = "root-b"
ingredient = "set-orientation"

[steps.arguments]
orientation = "Portrait"

[[steps]]
id = "root-a"
ingredient = "set-textscale"

[steps.arguments]
text_scale_percent = 150

[[steps]]
id = "after-a"
ingredient = "set-resolution"
depends_on = ["root-a"]

[steps.arguments]
width = 1280
height = 720

[[steps]]
id = "after-b"
ingredient = "set-uiscale"
depends_on = ["root-b"]

[steps.arguments]
ui_scale_percent = 125
"@ | Set-Content -LiteralPath $recipePath -Encoding UTF8
            $recipe = Get-ParsecRecipeDocument -NameOrPath $recipePath

            $result = Invoke-ParsecRecipeSequence -Recipe $recipe -StateRoot $stateRoot

            $result.terminal_status | Should -Be 'Succeeded'
            @($result.step_results.step_id) | Should -Be @('root-b', 'root-a', 'after-b', 'after-a')
        }

        It 'rolls back earlier successful explicit-compensation steps in reverse order after a later failure' {
            $stateRoot = Join-Path $TestDrive 'reverse-rollback'
            $recipePath = Join-Path $TestDrive 'reverse-rollback.toml'
            @"
name = "reverse-rollback"

[[steps]]
id = "set-good-resolution"
ingredient = "set-resolution"
compensation_policy = "explicit"

[steps.arguments]
width = 1280
height = 720

[[steps]]
id = "fail-command"
ingredient = "command.invoke"
depends_on = ["set-good-resolution"]
compensation_policy = "explicit"

[steps.arguments]
file_path = "cmd.exe"
arguments = ["/c", "exit", "7"]
"@ | Set-Content -LiteralPath $recipePath -Encoding UTF8
            $recipe = Get-ParsecRecipeDocument -NameOrPath $recipePath

            $result = Invoke-ParsecRecipeSequence -Recipe $recipe -StateRoot $stateRoot

            $result.terminal_status | Should -Be 'RolledBack'
            $result.rollback_status | Should -Be 'Succeeded'
            @($result.rollback_results).Count | Should -Be 1
            $result.rollback_results[0].step_id | Should -Be 'set-good-resolution'
            $script:IngredientObservedState.monitors[0].bounds.width | Should -Be 1920
            $result.step_results[0].status | Should -Be 'Succeeded'
            $result.step_results[1].status | Should -Be 'Failed'
        }

        It 'executes a no-mode resolution recipe through the standalone ingredient pipeline' {
            $stateRoot = Join-Path $TestDrive 'resolution-sequence'
            $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\resolution-sequence.toml'
            $recipe = Get-ParsecRecipeDocument -NameOrPath $recipePath

            $result = Invoke-ParsecRecipeSequence -Recipe $recipe -StateRoot $stateRoot

            $result.recipe_name | Should -Be 'resolution-sequence'
            $result.terminal_status | Should -Be 'Succeeded'
            $result.step_results[0].ingredient | Should -Be 'display.set-resolution'
            $result.step_results[0].token_id | Should -Not -BeNullOrEmpty
            $script:IngredientObservedState.monitors[0].bounds.width | Should -Be 1280
        }

        It 'blocks dependent steps when resolution readiness times out' {
            $stateRoot = Join-Path $TestDrive 'resolution-readiness-blocks'
            $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\resolution-readiness-blocks.toml'
            $recipe = Get-ParsecRecipeDocument -NameOrPath $recipePath
            $definition = Get-ParsecCoreIngredientDefinition -Name 'set-resolution'
            $originalReadiness = ConvertTo-ParsecPlainObject -InputObject $definition.Readiness

            try {
                $definition.Readiness.timeout_ms = 10
                $definition.Readiness.poll_interval_ms = 1
                $definition.Readiness.success_count = 2
                $script:IngredientResolutionObservationLagRemaining = 100

                $result = Invoke-ParsecRecipeSequence -Recipe $recipe -StateRoot $stateRoot

                $result.terminal_status | Should -Be 'Failed'
                $result.step_results[0].status | Should -Be 'Failed'
                $result.step_results[0].readiness_result.Errors | Should -Contain 'ReadinessTimeout'
                $result.step_results[1].status | Should -Be 'Blocked'
            }
            finally {
                $definition.Readiness = ConvertTo-ParsecPlainObject -InputObject $originalReadiness
            }
        }

        It 'skips steps whose mode condition evaluates to false' {
            $stateRoot = Join-Path $TestDrive 'condition-skips'
            $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\condition-skips.toml'
            $recipe = Get-ParsecRecipeDocument -NameOrPath $recipePath

            $result = Invoke-ParsecRecipeSequence -Recipe $recipe -StateRoot $stateRoot

            $result.terminal_status | Should -Be 'Succeeded'
            $result.step_results[0].status | Should -Be 'Skipped'
            $result.step_results[0].message | Should -Be 'Step condition evaluated to false.'
            $script:IngredientObservedState.monitors[0].bounds.width | Should -Be 1920
            $script:IngredientObservedState.monitors[0].bounds.height | Should -Be 1080
        }

        It 'shares active snapshot state across non-apply sequence steps' {
            $stateRoot = Join-Path $TestDrive 'snapshot-sequence'
            $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\snapshot-sequence.toml'
            $recipe = Get-ParsecRecipeDocument -NameOrPath $recipePath

            $result = Invoke-ParsecRecipeSequence -Recipe $recipe -StateRoot $stateRoot

            $result.terminal_status | Should -Be 'Succeeded'
            $result.step_results[0].status | Should -Be 'Succeeded'
            $result.step_results[1].status | Should -Be 'Succeeded'
            $result.step_results[2].status | Should -Be 'Succeeded'
            $result.step_results[2].operation_result.Outputs.snapshot_name | Should -Be 'desktop-pre-parsec'
            $script:IngredientObservedState.monitors[0].bounds.width | Should -Be 1920
            $script:IngredientObservedState.monitors[0].bounds.height | Should -Be 1080
        }

        It 'executes an active-display recipe through the standalone ingredient pipeline' {
            $stateRoot = Join-Path $TestDrive 'active-display-sequence'
            $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\active-display-sequence.toml'
            $recipe = Get-ParsecRecipeDocument -NameOrPath $recipePath
            Enable-ParsecIngredientDualMonitorEnvironment

            $result = Invoke-ParsecRecipeSequence -Recipe $recipe -StateRoot $stateRoot

            $result.recipe_name | Should -Be 'active-display-sequence'
            $result.terminal_status | Should -Be 'Succeeded'
            $result.step_results[0].ingredient | Should -Be 'display.set-activedisplays'
            (@($script:IngredientObservedState.monitors | Where-Object { $_.enabled })).Count | Should -Be 1
            (@($script:IngredientObservedState.monitors | Where-Object { $_.enabled })[0].device_name) | Should -Be '\\.\DISPLAY1'
        }

        It 'executes an orientation recipe through the standalone ingredient pipeline' {
            $stateRoot = Join-Path $TestDrive 'orientation-sequence'
            $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\orientation-sequence.toml'
            $recipe = Get-ParsecRecipeDocument -NameOrPath $recipePath

            $result = Invoke-ParsecRecipeSequence -Recipe $recipe -StateRoot $stateRoot

            $result.recipe_name | Should -Be 'orientation-sequence'
            $result.terminal_status | Should -Be 'Succeeded'
            $result.step_results[0].ingredient | Should -Be 'display.set-orientation'
            $script:IngredientObservedState.monitors[0].orientation | Should -Be 'Portrait'
        }

        It 'executes a text-scale recipe through the standalone ingredient pipeline' {
            $stateRoot = Join-Path $TestDrive 'textscale-sequence'
            $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\textscale-sequence.toml'
            $recipe = Get-ParsecRecipeDocument -NameOrPath $recipePath

            $result = Invoke-ParsecRecipeSequence -Recipe $recipe -StateRoot $stateRoot

            $result.recipe_name | Should -Be 'textscale-sequence'
            $result.terminal_status | Should -Be 'Succeeded'
            $result.step_results[0].ingredient | Should -Be 'display.set-textscale'
            $script:IngredientObservedState.font_scaling.text_scale_percent | Should -Be 150
        }

        It 'executes a UI-scale recipe through the standalone ingredient pipeline' {
            $stateRoot = Join-Path $TestDrive 'uiscale-sequence'
            $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\uiscale-sequence.toml'
            $recipe = Get-ParsecRecipeDocument -NameOrPath $recipePath

            $result = Invoke-ParsecRecipeSequence -Recipe $recipe -StateRoot $stateRoot

            $result.recipe_name | Should -Be 'uiscale-sequence'
            $result.terminal_status | Should -Be 'Succeeded'
            $result.step_results[0].ingredient | Should -Be 'display.set-uiscale'
            $result.step_results[0].readiness_result.Status | Should -Be 'Succeeded'
            $script:IngredientObservedState.scaling.ui_scale_percent | Should -Be 125
        }
    }
}
