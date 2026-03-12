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

        It 'upgrades fallback display catalog identities without changing screen ids' {
            $stateRoot = Join-Path $TestDrive 'display-catalog-upgrade'
            $originalIdentity = ConvertTo-ParsecPlainObject -InputObject $script:IngredientObservedState.monitors[0].identity
            $originalDevicePath = [string] $script:IngredientObservedState.monitors[0].monitor_device_path

            $script:IngredientObservedState.monitors[0].identity = $null
            $script:IngredientObservedState.monitors[0].monitor_device_path = $null
            $first = @(Get-ParsecDisplay -StateRoot $stateRoot)

            $script:IngredientObservedState.monitors[0].identity = $originalIdentity
            $script:IngredientObservedState.monitors[0].monitor_device_path = $originalDevicePath
            $second = @(Get-ParsecDisplay -StateRoot $stateRoot)
            $catalog = Get-ParsecDisplayCatalogDocument -StateRoot $stateRoot

            $first[0].screen_id | Should -Be 1
            $second[0].screen_id | Should -Be 1
            @($catalog.entries).Count | Should -Be 1
            $catalog.entries[0].identity_key | Should -Be 'adapter_id+target_id:00000000:00000001:1'
        }

        It 'does not rewrite the display catalog when the observed state is unchanged' {
            $stateRoot = Join-Path $TestDrive 'display-catalog-stable'
            $catalogPath = Join-Path $stateRoot 'display-catalog.json'

            $null = @(Get-ParsecDisplay -StateRoot $stateRoot)
            $firstCatalog = Get-Content -LiteralPath $catalogPath -Raw

            $null = @(Get-ParsecDisplay -StateRoot $stateRoot)
            $secondCatalog = Get-Content -LiteralPath $catalogPath -Raw

            $secondCatalog | Should -BeExactly $firstCatalog
        }

        It 'validates argument types before invoking the ingredient runtime' {
            $stateRoot = Join-Path $TestDrive 'invalid-arguments'

            {
                Invoke-ParsecIngredient -Name 'set-resolution' -Arguments @{
                    width = 'wide'
                    height = 720
                } -StateRoot $stateRoot -Confirm:$false
            } | Should -Throw "*argument 'width' must be of type 'integer'*"
        }

        It 'accepts a flat ingredient alias and persists a reusable token on apply' {
            $stateRoot = Join-Path $TestDrive 'alias-apply'

            $result = Invoke-ParsecIngredient -Name 'set-resolution' -Arguments @{
                width = 1280
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

        It 'waits for readiness before succeeding when the resolution converges after delayed observations' {
            $stateRoot = Join-Path $TestDrive 'delayed-readiness'
            $definition = Get-ParsecIngredientDefinition -Name 'set-resolution'
            $definition.Readiness.timeout_ms = 100
            $definition.Readiness.poll_interval_ms = 1
            $definition.Readiness.success_count = 2
            $script:IngredientResolutionObservationLagRemaining = 2

            $result = Invoke-ParsecIngredient -Name 'set-resolution' -Arguments @{
                width = 1280
                height = 720
            } -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'Succeeded'
            $result.readiness_result.Status | Should -Be 'Succeeded'
            $result.readiness_result.Outputs.attempts | Should -BeGreaterThan 1
            $result.readiness_result.Outputs.successful_probes | Should -Be 2
            $result.verify_result.Status | Should -Be 'Succeeded'
        }

        It 'requires an explicit token for reset and restores the captured resolution' {
            $stateRoot = Join-Path $TestDrive 'reset-token'

            {
                Invoke-ParsecIngredient -Name 'set-resolution' -Operation 'reset' -StateRoot $stateRoot -Confirm:$false
            } | Should -Throw "*requires -TokenId*"

            $apply = Invoke-ParsecIngredient -Name 'set-resolution' -Arguments @{
                width = 1280
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
                width = 1280
                height = 720
            } -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'Succeeded'
            $result.operation_result.Outputs.device_name | Should -Be '\\.\DISPLAY1'
        }

        It 'returns supported mode data when the requested resolution is unavailable' {
            $stateRoot = Join-Path $TestDrive 'unsupported-resolution'

            $result = Invoke-ParsecIngredient -Name 'set-resolution' -Arguments @{
                width = 1600
                height = 900
            } -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'Failed'
            $result.operation_result.Errors | Should -Contain 'UnsupportedResolution'
            $result.operation_result.Outputs.supported_mode_count | Should -Be 2
            $result.operation_result.Outputs.supported_modes_sample[0].width | Should -Be 1280
        }

        It 'fails when readiness times out before the display converges to the requested resolution' {
            $stateRoot = Join-Path $TestDrive 'readiness-timeout'
            $definition = Get-ParsecIngredientDefinition -Name 'set-resolution'
            $definition.Readiness.timeout_ms = 10
            $definition.Readiness.poll_interval_ms = 1
            $definition.Readiness.success_count = 2
            $script:IngredientResolutionObservationLagRemaining = 100

            $result = Invoke-ParsecIngredient -Name 'set-resolution' -Arguments @{
                width = 1280
                height = 720
            } -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'Failed'
            $result.readiness_result.Errors | Should -Contain 'ReadinessTimeout'
            $result.verify_result | Should -BeNullOrEmpty
        }

        It 'fails verification when the display backend drifts from the requested resolution' {
            $stateRoot = Join-Path $TestDrive 'resolution-drift'
            $definition = Get-ParsecIngredientDefinition -Name 'set-resolution'
            $waitOperation = $definition.Operations['wait']
            $definition.Operations.Remove('wait')
            $script:IngredientResolutionMutationEnabled = $false

            try {
                $result = Invoke-ParsecIngredient -Name 'set-resolution' -Arguments @{
                    width = 1280
                    height = 720
                } -StateRoot $stateRoot -Confirm:$false
            }
            finally {
                $definition.Operations['wait'] = $waitOperation
            }

            $result.status | Should -Be 'Failed'
            $result.verify_result.Errors | Should -Contain 'ResolutionDrift'
            $result.verify_result.Observed.bounds.width | Should -Be 1920
        }

        It 'allows standalone apply to skip verification explicitly' {
            $stateRoot = Join-Path $TestDrive 'skip-verify'
            $definition = Get-ParsecIngredientDefinition -Name 'set-resolution'
            $waitOperation = $definition.Operations['wait']
            $definition.Operations.Remove('wait')
            $script:IngredientResolutionMutationEnabled = $false

            try {
                $result = Invoke-ParsecIngredient -Name 'set-resolution' -Arguments @{
                    width = 1280
                    height = 720
                } -Verify:$false -StateRoot $stateRoot -Confirm:$false
            }
            finally {
                $definition.Operations['wait'] = $waitOperation
            }

            $result.status | Should -Be 'Succeeded'
            $result.verify_result | Should -BeNullOrEmpty
        }

        It 'applies a screen-id based orientation change through the standalone ingredient surface' {
            $stateRoot = Join-Path $TestDrive 'orientation-screen-id'
            $display = @(Get-ParsecDisplay -StateRoot $stateRoot) | Select-Object -First 1

            $result = Invoke-ParsecIngredient -Name 'set-orientation' -Arguments @{
                screen_id = $display.screen_id
                orientation = 'Portrait'
            } -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'Succeeded'
            $result.ingredient_name | Should -Be 'display.set-orientation'
            $result.operation_result.Outputs.device_name | Should -Be '\\.\DISPLAY1'
            $script:IngredientObservedState.monitors[0].orientation | Should -Be 'Portrait'
        }

        It 'waits for readiness before succeeding when the orientation converges after delayed observations' {
            $stateRoot = Join-Path $TestDrive 'orientation-delayed-readiness'
            $definition = Get-ParsecIngredientDefinition -Name 'set-orientation'
            $originalReadiness = ConvertTo-ParsecPlainObject -InputObject $definition.Readiness

            try {
                $definition.Readiness.timeout_ms = 100
                $definition.Readiness.poll_interval_ms = 1
                $definition.Readiness.success_count = 2
                $script:IngredientOrientationObservationLagRemaining = 2

                $result = Invoke-ParsecIngredient -Name 'set-orientation' -Arguments @{
                    orientation = 'Portrait'
                } -StateRoot $stateRoot -Confirm:$false

                $result.status | Should -Be 'Succeeded'
                $result.readiness_result.Status | Should -Be 'Succeeded'
                $result.readiness_result.Outputs.attempts | Should -BeGreaterThan 1
                $result.readiness_result.Outputs.successful_probes | Should -Be 2
                $result.verify_result.Status | Should -Be 'Succeeded'
            }
            finally {
                $definition.Readiness = ConvertTo-ParsecPlainObject -InputObject $originalReadiness
            }
        }

        It 'fails when readiness times out before the orientation converges' {
            $stateRoot = Join-Path $TestDrive 'orientation-readiness-timeout'
            $definition = Get-ParsecIngredientDefinition -Name 'set-orientation'
            $originalReadiness = ConvertTo-ParsecPlainObject -InputObject $definition.Readiness

            try {
                $definition.Readiness.timeout_ms = 10
                $definition.Readiness.poll_interval_ms = 1
                $definition.Readiness.success_count = 2
                $script:IngredientOrientationObservationLagRemaining = 100

                $result = Invoke-ParsecIngredient -Name 'set-orientation' -Arguments @{
                    orientation = 'Portrait'
                } -StateRoot $stateRoot -Confirm:$false

                $result.status | Should -Be 'Failed'
                $result.readiness_result.Errors | Should -Contain 'ReadinessTimeout'
                $result.verify_result | Should -BeNullOrEmpty
            }
            finally {
                $definition.Readiness = ConvertTo-ParsecPlainObject -InputObject $originalReadiness
            }
        }

        It 'captures and restores persisted topology snapshots explicitly' {
            $stateRoot = Join-Path $TestDrive 'persist-topology'

            $capture = Invoke-ParsecIngredient -Name 'persist-topology' -Operation 'capture' -Arguments @{
                snapshot_name = 'topology-standalone'
            } -StateRoot $stateRoot -Confirm:$false

            $script:IngredientObservedState.monitors[0].bounds.x = 480
            $script:IngredientObservedState.monitors[0].bounds.y = 220
            $script:IngredientObservedState.monitors[0].bounds.width = 1280
            $script:IngredientObservedState.monitors[0].bounds.height = 720
            $script:IngredientObservedState.monitors[0].display.width = 1280
            $script:IngredientObservedState.monitors[0].display.height = 720
            $script:IngredientObservedState.monitors[0].orientation = 'Portrait'

            $reset = Invoke-ParsecIngredientOperation -Name 'display.persist-topology' -Operation 'reset' -Arguments @{
                snapshot_name = 'topology-standalone'
            } -StateRoot $stateRoot

            $verify = Invoke-ParsecIngredientOperation -Name 'display.persist-topology' -Operation 'verify' -Arguments @{
                snapshot_name = 'topology-standalone'
            } -StateRoot $stateRoot

            $capture.status | Should -Be 'Succeeded'
            $reset.status | Should -Be 'Succeeded'
            $verify.status | Should -Be 'Succeeded'
            $script:IngredientObservedState.monitors[0].bounds.x | Should -Be 0
            $script:IngredientObservedState.monitors[0].bounds.width | Should -Be 1920
            $script:IngredientObservedState.monitors[0].orientation | Should -Be 'Landscape'
        }

        It 'applies and resets an active-display selection through the standalone ingredient surface' {
            $stateRoot = Join-Path $TestDrive 'active-displays'
            Enable-ParsecIngredientDualMonitorEnvironment
            $inventory = @(Get-ParsecDisplay -StateRoot $stateRoot)

            $result = Invoke-ParsecIngredient -Name 'set-activedisplays' -Arguments @{
                screen_ids = @($inventory[0].screen_id)
            } -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'Succeeded'
            $result.ingredient_name | Should -Be 'display.set-activedisplays'
            $result.token_id | Should -Not -BeNullOrEmpty
            (@($script:IngredientObservedState.monitors | Where-Object { $_.enabled })).Count | Should -Be 1
            (@($script:IngredientObservedState.monitors | Where-Object { $_.enabled })[0].device_name) | Should -Be '\\.\DISPLAY1'

            $reset = Invoke-ParsecIngredient -Name 'set-activedisplays' -Operation 'reset' -TokenId $result.token_id -StateRoot $stateRoot -Confirm:$false

            $reset.status | Should -Be 'Succeeded'
            (@($script:IngredientObservedState.monitors | Where-Object { $_.enabled })).Count | Should -Be 2
        }

        It 'ignores a caller supplied token id for apply when the ingredient does not capture state' {
            $stateRoot = Join-Path $TestDrive 'apply-ignores-token'

            $result = Invoke-ParsecIngredient -Name 'nvidia-add-custom-resolution' -Arguments @{
                width = 1600
                height = 900
            } -TokenId 'caller-token' -Verify:$false -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'Succeeded'
            $result.token_id | Should -BeNullOrEmpty
            $result.token_path | Should -BeNullOrEmpty
            $result.operation_result.Outputs.width | Should -Be 1600
            $result.operation_result.Outputs.height | Should -Be 900
        }
    }
}
