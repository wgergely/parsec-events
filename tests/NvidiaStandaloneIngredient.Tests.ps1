$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

Describe 'NVIDIA standalone ingredient surface' {
    InModuleScope ParsecEventExecutor {
        BeforeEach {
            . (Join-Path $PSScriptRoot 'IngredientTestSupport.ps1')
            Initialize-ParsecIngredientTestEnvironment
        }

        It 'applies without creating a rollback token for a persistent NVIDIA ingredient' {
            $stateRoot = Join-Path $TestDrive 'nvidia-persistent'

            $result = Invoke-ParsecIngredient -Name 'nvidia.add-custom-resolution' -Arguments @{
                width = 2000
                height = 1125
            } -StateRoot $stateRoot -Confirm:$false

            $result.ingredient_name | Should -Be 'nvidia.add-custom-resolution'
            $result.status | Should -Be 'Succeeded'
            $result.token_id | Should -BeNullOrEmpty
            $result.readiness_result.Status | Should -Be 'Succeeded'
            $result.verify_result.Status | Should -Be 'Succeeded'
            $result.operation_result.Outputs.topology_restore.Status | Should -Be 'Succeeded'
            $script:IngredientObservedState.monitors[0].bounds.width | Should -Be 1920
            $script:IngredientObservedState.monitors[0].bounds.x | Should -Be 0
        }

        It 'waits until the new custom resolution appears in supported display modes' {
            $stateRoot = Join-Path $TestDrive 'nvidia-wait'
            $definition = Get-ParsecIngredientDefinition -Name 'nvidia.add-custom-resolution'
            $definition.Readiness.timeout_ms = 100
            $definition.Readiness.poll_interval_ms = 1
            $definition.Readiness.success_count = 2
            $script:IngredientNvidiaSupportedModeLagRemaining = 2

            $result = Invoke-ParsecIngredient -Name 'nvidia.add-custom-resolution' -Arguments @{
                width = 2000
                height = 1125
            } -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'Succeeded'
            $result.readiness_result.Status | Should -Be 'Succeeded'
            $result.readiness_result.Outputs.attempts | Should -BeGreaterThan 1
            $result.readiness_result.Outputs.successful_probes | Should -Be 2
        }

        It 'fails when the supported mode list never converges to the saved custom resolution' {
            $stateRoot = Join-Path $TestDrive 'nvidia-timeout'
            $definition = Get-ParsecIngredientDefinition -Name 'nvidia.add-custom-resolution'
            $definition.Readiness.timeout_ms = 10
            $definition.Readiness.poll_interval_ms = 1
            $definition.Readiness.success_count = 2
            $script:IngredientNvidiaSupportedModeLagRemaining = 100

            $result = Invoke-ParsecIngredient -Name 'nvidia.add-custom-resolution' -Arguments @{
                width = 2000
                height = 1125
            } -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'Failed'
            $result.readiness_result.Errors | Should -Contain 'ReadinessTimeout'
            $result.verify_result | Should -BeNullOrEmpty
        }

        It 'fails before NVAPI when the requested orientation does not match the active monitor orientation' {
            $stateRoot = Join-Path $TestDrive 'nvidia-orientation-mismatch'

            $result = Invoke-ParsecIngredient -Name 'nvidia.add-custom-resolution' -Arguments @{
                width = 1125
                height = 2000
            } -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'Failed'
            $result.operation_result.Errors | Should -Contain 'OrientationMismatch'
        }
    }
}
