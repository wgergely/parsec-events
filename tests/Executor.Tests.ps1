$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

Describe 'Invoke-ParsecRecipe' {
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
    }
}
