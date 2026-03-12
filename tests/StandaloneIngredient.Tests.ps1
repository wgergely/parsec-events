$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

Describe 'Standalone ingredient surface' {
    InModuleScope ParsecEventExecutor {
        BeforeEach {
            . (Join-Path $PSScriptRoot 'IngredientTestSupport.ps1')
            Initialize-ParsecIngredientTestEnvironment
        }

        It 'returns stable screen ids from the persisted display catalog' {
            $stateRoot = Join-Path $TestDrive 'display-catalog'

            $first = @(Get-ParsecDisplay -StateRoot $stateRoot)
            $script:IngredientObservedState.monitors[0].device_name = '\\.\DISPLAY9'
            $script:IngredientObservedState.monitors[0].source_name = '\\.\DISPLAY9'
            $second = @(Get-ParsecDisplay -StateRoot $stateRoot)

            $first.Count | Should -Be 1
            $first[0].screen_id | Should -Be 1
            $second[0].screen_id | Should -Be 1
            $second[0].identity.adapter_id | Should -Be '00000000:00000001'
        }

        It 'validates argument types before invoking the ingredient runtime' {
            $stateRoot = Join-Path $TestDrive 'invalid-arguments'

            {
                Invoke-ParsecIngredient -Name 'set-resolution' -Arguments @{
                    width  = 'wide'
                    height = 720
                } -StateRoot $stateRoot -Confirm:$false
            } | Should -Throw "*argument 'width' must be of type 'integer'*"
        }

        It 'accepts a flat ingredient alias and persists a reusable token on apply' {
            $stateRoot = Join-Path $TestDrive 'alias-apply'

            $result = Invoke-ParsecIngredient -Name 'set-resolution' -Arguments @{
                width  = 1280
                height = 720
            } -StateRoot $stateRoot -Confirm:$false

            $result.ingredient_name | Should -Be 'display.set-resolution'
            $result.status | Should -Be 'Succeeded'
            $result.token_id | Should -Not -BeNullOrEmpty
            $result.operation_result.Outputs.device_name | Should -Be '\\.\DISPLAY1'
            (Test-Path -LiteralPath $result.token_path) | Should -BeTrue

            $tokenDocument = Get-Content -LiteralPath $result.token_path -Raw | ConvertFrom-Json -Depth 100
            $tokenDocument.payload.requested_name | Should -Be 'set-resolution'
            $tokenDocument.payload.captured_state.bounds.width | Should -Be 1920
            $tokenDocument.payload.apply_status | Should -Be 'Succeeded'
        }

        It 'requires an explicit token for reset and restores the captured resolution' {
            $stateRoot = Join-Path $TestDrive 'reset-token'

            {
                Invoke-ParsecIngredient -Name 'set-resolution' -Operation 'reset' -StateRoot $stateRoot -Confirm:$false
            } | Should -Throw "*requires -TokenId*"

            $apply = Invoke-ParsecIngredient -Name 'set-resolution' -Arguments @{
                width  = 1280
                height = 720
            } -StateRoot $stateRoot -Confirm:$false

            $script:IngredientObservedState.monitors[0].bounds.width | Should -Be 1280

            $reset = Invoke-ParsecIngredient -Name 'set-resolution' -Operation 'reset' -TokenId $apply.token_id -StateRoot $stateRoot -Confirm:$false

            $reset.status | Should -Be 'Succeeded'
            $script:IngredientObservedState.monitors[0].bounds.width | Should -Be 1920

            $tokenDocument = Get-Content -LiteralPath $apply.token_path -Raw | ConvertFrom-Json -Depth 100
            $tokenDocument.payload.reset_status | Should -Be 'ResetSucceeded'
        }

        It 'resolves an explicit screen id to the canonical display target' {
            $stateRoot = Join-Path $TestDrive 'screen-id'
            $display = @(Get-ParsecDisplay -StateRoot $stateRoot) | Select-Object -First 1

            $result = Invoke-ParsecIngredient -Name 'set-resolution' -Arguments @{
                screen_id = $display.screen_id
                width     = 1280
                height    = 720
            } -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'Succeeded'
            $result.operation_result.Outputs.device_name | Should -Be '\\.\DISPLAY1'
        }

        It 'returns supported mode data when the requested resolution is unavailable' {
            $stateRoot = Join-Path $TestDrive 'unsupported-resolution'

            $result = Invoke-ParsecIngredient -Name 'set-resolution' -Arguments @{
                width  = 1600
                height = 900
            } -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'Failed'
            $result.operation_result.Errors | Should -Contain 'UnsupportedResolution'
            $result.operation_result.Outputs.supported_mode_count | Should -Be 2
            $result.operation_result.Outputs.supported_modes_sample[0].width | Should -Be 1280
        }

        It 'fails verification when the display backend drifts from the requested resolution' {
            $stateRoot = Join-Path $TestDrive 'resolution-drift'
            $script:IngredientResolutionMutationEnabled = $false

            $result = Invoke-ParsecIngredient -Name 'set-resolution' -Arguments @{
                width  = 1280
                height = 720
            } -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'Failed'
            $result.verify_result.Errors | Should -Contain 'ResolutionDrift'
            $result.verify_result.Observed.bounds.width | Should -Be 1920
        }
    }
}
