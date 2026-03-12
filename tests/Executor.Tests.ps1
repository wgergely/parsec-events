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
                id = 'stop-service'
                ingredient = 'service.stop'
                operation = 'apply'
                depends_on = @()
                arguments = @{ service_name = 'Spooler' }
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
                    ingredient_name = 'service.stop'
                    status = 'Failed'
                    token_id = 'captured-token'
                    token_path = 'Y:\fake-token.json'
                    capture_result = @{ Status = 'Succeeded' }
                    operation_result = @{ Status = 'Failed'; Message = 'Stop failed.' }
                    readiness_result = $null
                    verify_result = $null
                    reset_result = $null
                    invocation_id = 'apply-invocation'
                    started_at = '2026-03-12T00:00:00.0000000+00:00'
                    completed_at = '2026-03-12T00:00:01.0000000+00:00'
                    message = 'Stop failed.'
                }
            } -ParameterFilter { $Name -eq 'service.stop' -and $Operation -eq 'apply' }

            $result = Invoke-ParsecRecipeSequenceStep -Step $step -RunRecord $runRecord -StateRoot $TestDrive

            $result.status | Should -Be 'Failed'
            $result.message | Should -Be 'Stop failed.'
            $result.compensation_result | Should -BeNullOrEmpty
            Should -Invoke Invoke-ParsecIngredientCommandInternal -Times 1 -Exactly -ParameterFilter { $Name -eq 'service.stop' -and $Operation -eq 'apply' }
            Should -Invoke Invoke-ParsecIngredientCommandInternal -Times 0 -Exactly -ParameterFilter { $Name -eq 'service.stop' -and $Operation -eq 'reset' }
        }
    }

    It 'executes a successful command recipe through the thin sequencer' {
        $stateRoot = Join-Path $TestDrive 'state-success'
        $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\command-success.toml'

        $result = Invoke-ParsecRecipe -NameOrPath $recipePath -StateRoot $stateRoot -Confirm:$false

        $result.terminal_status | Should -Be 'Succeeded'
        $result.step_results[0].status | Should -Be 'Succeeded'
        $result.step_results[0].invocation_id | Should -Not -BeNullOrEmpty
        (Test-Path (Join-Path $stateRoot 'executor-state.json')) | Should -BeFalse
        (Get-ChildItem -Path (Join-Path $stateRoot 'ingredient-invocations') -File).Count | Should -Be 1
    }

    It 'blocks dependent steps after a failure' {
        $stateRoot = Join-Path $TestDrive 'state-failure'
        $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\failure-blocks.toml'

        $result = Invoke-ParsecRecipe -NameOrPath $recipePath -StateRoot $stateRoot -Confirm:$false

        $result.terminal_status | Should -Be 'Failed'
        $result.step_results[0].status | Should -Be 'Failed'
        $result.step_results[1].status | Should -Be 'Blocked'
    }

    InModuleScope ParsecEventExecutor {
        BeforeEach {
            . (Join-Path $PSScriptRoot 'IngredientTestSupport.ps1')
            Initialize-ParsecIngredientTestEnvironment
        }

        It 'executes a no-mode resolution recipe through the standalone ingredient pipeline' {
            $stateRoot = Join-Path $TestDrive 'resolution-sequence'
            $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\resolution-sequence.toml'

            $result = Invoke-ParsecRecipe -NameOrPath $recipePath -StateRoot $stateRoot -Confirm:$false

            $result.recipe_name | Should -Be 'resolution-sequence'
            $result.terminal_status | Should -Be 'Succeeded'
            $result.step_results[0].ingredient | Should -Be 'display.set-resolution'
            $result.step_results[0].token_id | Should -Not -BeNullOrEmpty
            $script:IngredientObservedState.monitors[0].bounds.width | Should -Be 1280
        }

        It 'blocks dependent steps when resolution readiness times out' {
            $stateRoot = Join-Path $TestDrive 'resolution-readiness-blocks'
            $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\resolution-readiness-blocks.toml'
            $definition = Get-ParsecIngredientDefinition -Name 'set-resolution'
            $originalReadiness = ConvertTo-ParsecPlainObject -InputObject $definition.Readiness

            try {
                $definition.Readiness.timeout_ms = 10
                $definition.Readiness.poll_interval_ms = 1
                $definition.Readiness.success_count = 2
                $script:IngredientResolutionObservationLagRemaining = 100

                $result = Invoke-ParsecRecipe -NameOrPath $recipePath -StateRoot $stateRoot -Confirm:$false

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

            $result = Invoke-ParsecRecipe -NameOrPath $recipePath -StateRoot $stateRoot -Confirm:$false

            $result.terminal_status | Should -Be 'Succeeded'
            $result.step_results[0].status | Should -Be 'Skipped'
            $result.step_results[0].message | Should -Be 'Step condition evaluated to false.'
            $script:IngredientObservedState.monitors[0].bounds.width | Should -Be 1920
            $script:IngredientObservedState.monitors[0].bounds.height | Should -Be 1080
        }

        It 'shares active snapshot state across non-apply sequence steps' {
            $stateRoot = Join-Path $TestDrive 'snapshot-sequence'
            $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\snapshot-sequence.toml'

            $result = Invoke-ParsecRecipe -NameOrPath $recipePath -StateRoot $stateRoot -Confirm:$false

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
            Enable-ParsecIngredientDualMonitorEnvironment

            $result = Invoke-ParsecRecipe -NameOrPath $recipePath -StateRoot $stateRoot -Confirm:$false

            $result.recipe_name | Should -Be 'active-display-sequence'
            $result.terminal_status | Should -Be 'Succeeded'
            $result.step_results[0].ingredient | Should -Be 'display.set-activedisplays'
            (@($script:IngredientObservedState.monitors | Where-Object { $_.enabled })).Count | Should -Be 1
            (@($script:IngredientObservedState.monitors | Where-Object { $_.enabled })[0].device_name) | Should -Be '\\.\DISPLAY1'
        }

        It 'executes an orientation recipe through the standalone ingredient pipeline' {
            $stateRoot = Join-Path $TestDrive 'orientation-sequence'
            $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\orientation-sequence.toml'

            $result = Invoke-ParsecRecipe -NameOrPath $recipePath -StateRoot $stateRoot -Confirm:$false

            $result.recipe_name | Should -Be 'orientation-sequence'
            $result.terminal_status | Should -Be 'Succeeded'
            $result.step_results[0].ingredient | Should -Be 'display.set-orientation'
            $script:IngredientObservedState.monitors[0].orientation | Should -Be 'Portrait'
        }

        It 'executes a text-scale recipe through the standalone ingredient pipeline' {
            $stateRoot = Join-Path $TestDrive 'textscale-sequence'
            $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\textscale-sequence.toml'

            $result = Invoke-ParsecRecipe -NameOrPath $recipePath -StateRoot $stateRoot -Confirm:$false

            $result.recipe_name | Should -Be 'textscale-sequence'
            $result.terminal_status | Should -Be 'Succeeded'
            $result.step_results[0].ingredient | Should -Be 'display.set-textscale'
            $script:IngredientObservedState.font_scaling.text_scale_percent | Should -Be 150
        }

        It 'executes a UI-scale recipe through the standalone ingredient pipeline' {
            $stateRoot = Join-Path $TestDrive 'uiscale-sequence'
            $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\uiscale-sequence.toml'

            $result = Invoke-ParsecRecipe -NameOrPath $recipePath -StateRoot $stateRoot -Confirm:$false

            $result.recipe_name | Should -Be 'uiscale-sequence'
            $result.terminal_status | Should -Be 'Succeeded'
            $result.step_results[0].ingredient | Should -Be 'display.set-uiscale'
            $result.step_results[0].readiness_result.Status | Should -Be 'Succeeded'
            $script:IngredientObservedState.scaling.ui_scale_percent | Should -Be 125
        }
    }
}
