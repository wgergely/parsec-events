$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

Describe 'Standalone ingredient surface' {
    InModuleScope ParsecEventExecutor {
        BeforeAll {
            . (Join-Path $PSScriptRoot 'IngredientTestSupport.ps1')
            $script:GuardStateRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("parsec-standalone-guard-{0}" -f ([Guid]::NewGuid().ToString('N')))
            $script:GuardSnapshotName = "standalone-guard-{0}" -f ([Guid]::NewGuid().ToString('N'))
            Clear-ParsecTestAdapters

            $guardCapture = Invoke-ParsecCoreIngredientOperation -Name 'display.snapshot' -Operation 'capture' -Arguments @{
                snapshot_name = $script:GuardSnapshotName
            } -StateRoot $script:GuardStateRoot -RunState @{}

            if (-not (Test-ParsecSuccessfulStatus -Status $guardCapture.Status)) {
                throw "Failed to capture the standalone test guard snapshot: $($guardCapture.Message)"
            }
        }

        BeforeEach {
            . (Join-Path $PSScriptRoot 'IngredientTestSupport.ps1')
            Initialize-ParsecIngredientTestEnvironment
            Initialize-ParsecCoreRuntime -Force
        }

        AfterEach {
            Clear-ParsecTestAdapters
            Initialize-ParsecCoreRuntime -Force

            $verifyArguments = @{
                snapshot_name = $script:GuardSnapshotName
            }
            $verify = Invoke-ParsecCoreIngredientOperation -Name 'display.snapshot' -Operation 'verify' -Arguments $verifyArguments -StateRoot $script:GuardStateRoot -RunState @{}
            if (-not (Test-ParsecSuccessfulStatus -Status $verify.Status)) {
                $reset = Invoke-ParsecCoreIngredientOperation -Name 'display.snapshot' -Operation 'reset' -Arguments $verifyArguments -StateRoot $script:GuardStateRoot -RunState @{}
                if (-not (Test-ParsecSuccessfulStatus -Status $reset.Status)) {
                    throw "Standalone test cleanup could not restore the guard snapshot: $($reset.Message)"
                }

                $postResetVerify = Invoke-ParsecCoreIngredientOperation -Name 'display.snapshot' -Operation 'verify' -Arguments $verifyArguments -StateRoot $script:GuardStateRoot -RunState @{}
                if (-not (Test-ParsecSuccessfulStatus -Status $postResetVerify.Status)) {
                    throw "Standalone test cleanup left the machine drifted after reset: $($postResetVerify.Message)"
                }
            }
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

        It 'registers ingredient packages through entry definitions' {
            $displayDefinition = Get-ParsecCoreIngredientDefinition -Name 'display.set-resolution'
            $commandDefinition = Get-ParsecCoreIngredientDefinition -Name 'command.invoke'

            $displayDefinition.Domain | Should -Be 'display'
            $displayDefinition.Metadata.package_format | Should -Be 'entry'
            $displayDefinition.Metadata.ingredient_path | Should -Match 'display-set-resolution'
            $commandDefinition.Domain | Should -Be 'command'
            $commandDefinition.Metadata.package_format | Should -Be 'entry'
            $commandDefinition.Metadata.ingredient_path | Should -Match 'command-invoke'
        }

        It 'requires domain metadata in ingredient schemas' {
            {
                Get-ParsecCoreRequiredIngredientDomain -Schema @{
                    name = 'display.set-resolution'
                    kind = 'display'
                }
            } | Should -Throw "*missing required 'domain' metadata*"
        }

        It 'rejects ingredient domain declarations that do not match the public naming contract' {
            {
                Get-ParsecCoreRequiredIngredientDomain -Schema @{
                    name = 'display.set-resolution'
                    domain = 'process'
                    kind = 'display'
                }
            } | Should -Throw "*public name requires domain 'display'*"
        }

        It 'does not expose the retired core observed-state bridge' {
            Get-Command -Name 'Get-ParsecObservedState' -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        }

        It 'keeps the window ingredient as a thin domain consumer' {
            $entryPath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\Private\Ingredients\window-cycle-activation\entry.ps1'
            $entry = Get-Content -LiteralPath $entryPath -Raw

            $entry | Should -Match 'DomainApi\.Invoke'
            $entry | Should -Not -Match 'GetForegroundWindowInfo'
            $entry | Should -Not -Match 'ActivateWindow'
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
            $definition = Get-ParsecCoreIngredientDefinition -Name 'set-resolution'
            $originalReadiness = ConvertTo-ParsecPlainObject -InputObject $definition.Readiness

            try {
                $definition.Readiness.timeout_ms = 1000
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
            finally {
                $definition.Readiness = ConvertTo-ParsecPlainObject -InputObject $originalReadiness
            }
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
            $definition = Get-ParsecCoreIngredientDefinition -Name 'set-resolution'
            $originalReadiness = ConvertTo-ParsecPlainObject -InputObject $definition.Readiness

            try {
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
            finally {
                $definition.Readiness = ConvertTo-ParsecPlainObject -InputObject $originalReadiness
            }
        }

        It 'reports verification drift when the display backend diverges after apply' {
            $stateRoot = Join-Path $TestDrive 'resolution-drift'
            $definition = Get-ParsecCoreIngredientDefinition -Name 'set-resolution'
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

            $result.status | Should -Be 'SucceededWithDrift'
            $result.verify_result.Errors | Should -Contain 'ResolutionDrift'
            $result.verify_result.Observed.bounds.width | Should -Be 1920
        }

        It 'allows standalone apply to skip verification explicitly' {
            $stateRoot = Join-Path $TestDrive 'skip-verify'
            $definition = Get-ParsecCoreIngredientDefinition -Name 'set-resolution'
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
            $definition = Get-ParsecCoreIngredientDefinition -Name 'set-orientation'
            $originalReadiness = ConvertTo-ParsecPlainObject -InputObject $definition.Readiness

            try {
                $definition.Readiness.timeout_ms = 1000
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
            $definition = Get-ParsecCoreIngredientDefinition -Name 'set-orientation'
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

        It 'applies and resets text scaling through the standalone ingredient surface' {
            $stateRoot = Join-Path $TestDrive 'textscale-apply-reset'

            $result = Invoke-ParsecIngredient -Name 'set-textscale' -Arguments @{
                text_scale_percent = 150
            } -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'Succeeded'
            $result.ingredient_name | Should -Be 'display.set-textscale'
            $result.token_id | Should -Not -BeNullOrEmpty
            $script:IngredientObservedState.font_scaling.text_scale_percent | Should -Be 150

            $reset = Invoke-ParsecIngredient -Name 'set-textscale' -Operation 'reset' -TokenId $result.token_id -StateRoot $stateRoot -Confirm:$false

            $reset.status | Should -Be 'Succeeded'
            $script:IngredientObservedState.font_scaling.text_scale_percent | Should -Be 130
        }

        It 'waits for readiness before succeeding when text scaling converges after delayed observations' {
            $stateRoot = Join-Path $TestDrive 'textscale-delayed-readiness'
            $definition = Get-ParsecCoreIngredientDefinition -Name 'set-textscale'
            $originalReadiness = ConvertTo-ParsecPlainObject -InputObject $definition.Readiness

            try {
                $definition.Readiness.timeout_ms = 1000
                $definition.Readiness.poll_interval_ms = 1
                $definition.Readiness.success_count = 2
                $script:IngredientTextScaleObservationLagRemaining = 2

                $result = Invoke-ParsecIngredient -Name 'set-textscale' -Arguments @{
                    text_scale_percent = 150
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

        It 'fails when readiness times out before text scaling converges' {
            $stateRoot = Join-Path $TestDrive 'textscale-readiness-timeout'
            $definition = Get-ParsecCoreIngredientDefinition -Name 'set-textscale'
            $originalReadiness = ConvertTo-ParsecPlainObject -InputObject $definition.Readiness

            try {
                $definition.Readiness.timeout_ms = 10
                $definition.Readiness.poll_interval_ms = 1
                $definition.Readiness.success_count = 2
                $script:IngredientTextScaleObservationLagRemaining = 100

                $result = Invoke-ParsecIngredient -Name 'set-textscale' -Arguments @{
                    text_scale_percent = 150
                } -StateRoot $stateRoot -Confirm:$false

                $result.status | Should -Be 'Failed'
                $result.readiness_result.Errors | Should -Contain 'ReadinessTimeout'
                $result.verify_result | Should -BeNullOrEmpty
            }
            finally {
                $definition.Readiness = ConvertTo-ParsecPlainObject -InputObject $originalReadiness
            }
        }

        It 'applies and resets UI scaling through the standalone ingredient surface' {
            $stateRoot = Join-Path $TestDrive 'uiscale-apply-reset'

            $result = Invoke-ParsecIngredient -Name 'set-uiscale' -Arguments @{
                ui_scale_percent = 125
            } -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'Succeeded'
            $result.ingredient_name | Should -Be 'display.set-uiscale'
            $result.token_id | Should -Not -BeNullOrEmpty
            $result.operation_result.Outputs.requires_signout | Should -BeTrue
            $script:IngredientObservedState.scaling.ui_scale_percent | Should -Be 125

            $reset = Invoke-ParsecIngredient -Name 'set-uiscale' -Operation 'reset' -TokenId $result.token_id -StateRoot $stateRoot -Confirm:$false

            $reset.status | Should -Be 'Succeeded'
            $script:IngredientObservedState.scaling.ui_scale_percent | Should -Be 150
        }

        It 'uses the applied UI scale from the adapter when the backend clamps the request' {
            $stateRoot = Join-Path $TestDrive 'uiscale-clamped'
            $script:IngredientUiScaleMinimum = 100
            $script:IngredientUiScaleMaximum = 125

            $result = Invoke-ParsecIngredient -Name 'set-uiscale' -Arguments @{
                ui_scale_percent = 80
            } -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'Succeeded'
            $result.operation_result.Outputs['ui_scale_percent'] | Should -Be 100
            $result.readiness_result.Status | Should -Be 'Succeeded'
            $result.readiness_result.Outputs.last_probe.Outputs['ui_scale_percent'] | Should -Be 100
            $result.verify_result.Status | Should -Be 'Succeeded'
            $result.verify_result.Outputs['ui_scale_percent'] | Should -Be 100
            $script:IngredientObservedState.scaling.ui_scale_percent | Should -Be 100
        }

        It 'waits for readiness before succeeding when UI scaling converges after delayed observations' {
            $stateRoot = Join-Path $TestDrive 'uiscale-delayed-readiness'
            $definition = Get-ParsecCoreIngredientDefinition -Name 'set-uiscale'
            $originalReadiness = ConvertTo-ParsecPlainObject -InputObject $definition.Readiness

            try {
                $definition.Readiness.timeout_ms = 1000
                $definition.Readiness.poll_interval_ms = 1
                $definition.Readiness.success_count = 2
                $script:IngredientUiScaleObservationLagRemaining = 2

                $result = Invoke-ParsecIngredient -Name 'set-uiscale' -Arguments @{
                    ui_scale_percent = 125
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

        It 'fails when readiness times out before UI scaling converges' {
            $stateRoot = Join-Path $TestDrive 'uiscale-readiness-timeout'
            $definition = Get-ParsecCoreIngredientDefinition -Name 'set-uiscale'
            $originalReadiness = ConvertTo-ParsecPlainObject -InputObject $definition.Readiness

            try {
                $definition.Readiness.timeout_ms = 10
                $definition.Readiness.poll_interval_ms = 1
                $definition.Readiness.success_count = 2
                $script:IngredientUiScaleObservationLagRemaining = 100

                $result = Invoke-ParsecIngredient -Name 'set-uiscale' -Arguments @{
                    ui_scale_percent = 125
                } -StateRoot $stateRoot -Confirm:$false

                $result.status | Should -Be 'Failed'
                $result.readiness_result.Errors | Should -Contain 'ReadinessTimeout'
                $result.verify_result | Should -BeNullOrEmpty
            }
            finally {
                $definition.Readiness = ConvertTo-ParsecPlainObject -InputObject $originalReadiness
            }
        }

        It 'cycles top-level windows and restores the original foreground window' {
            $stateRoot = Join-Path $TestDrive 'window-cycle'

            $result = Invoke-ParsecIngredient -Name 'cycle-activation' -Arguments @{
                dwell_ms = 0
                max_cycles = 4
            } -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'Succeeded'
            $result.ingredient_name | Should -Be 'window.cycle-activation'
            $result.operation_result.Outputs.alt_tab_candidates.Count | Should -Be 2
            $result.operation_result.Outputs.activation_results.Count | Should -Be 1
            $result.operation_result.Outputs.restore_result.succeeded | Should -BeTrue
            $result.verify_result.Status | Should -Be 'Succeeded'
            $script:IngredientWindowForegroundHandle | Should -Be 101
            $script:IngredientWindowActivationLog | Should -Be @(102, 101)
        }

        It 'restores the original foreground window through reset when activation drift occurs' {
            $stateRoot = Join-Path $TestDrive 'window-cycle-reset'

            $apply = Invoke-ParsecIngredient -Name 'cycle-activation' -Arguments @{
                dwell_ms = 0
                max_cycles = 4
            } -StateRoot $stateRoot -Confirm:$false

            $script:IngredientWindowForegroundHandle = 102
            $reset = Invoke-ParsecIngredient -Name 'cycle-activation' -Operation 'reset' -TokenId $apply.token_id -StateRoot $stateRoot -Confirm:$false

            $reset.status | Should -Be 'Succeeded'
            $script:IngredientWindowForegroundHandle | Should -Be 101
        }

        It 'persists compact invocation payloads for noisy window cycle results' {
            $stateRoot = Join-Path $TestDrive 'window-cycle-persistence'
            $script:IngredientWindows = @(
                [ordered]@{
                    handle = [int64] 101
                    owner_handle = [int64] 0
                    process_id = 1001
                    process_name = 'Code'
                    title = 'Editor'
                    class_name = 'ApplicationFrameWindow'
                    is_visible = $true
                    is_minimized = $false
                    is_cloaked = $false
                    is_shell_window = $false
                    extended_style = 0
                    width = 1440
                    height = 900
                }
            ) + @(
                foreach ($index in 200..230) {
                    [ordered]@{
                        handle = [int64] $index
                        owner_handle = [int64] 0
                        process_id = [int] (3000 + $index)
                        process_name = 'TestApp'
                        title = "App $index"
                        class_name = 'Chrome_WidgetWin_1'
                        is_visible = $true
                        is_minimized = $false
                        is_cloaked = $false
                        is_shell_window = $false
                        extended_style = 0
                        width = 1280
                        height = 720
                    }
                }
            )

            $result = Invoke-ParsecIngredient -Name 'cycle-activation' -Arguments @{
                dwell_ms = 0
                max_cycles = 30
            } -StateRoot $stateRoot -Confirm:$false

            $invocationDocument = Get-Content -LiteralPath $result.invocation_path -Raw | ConvertFrom-Json -Depth 100
            $persistedActivationResults = $invocationDocument.payload.operation_result.Outputs.activation_results

            $persistedActivationResults.truncated | Should -BeTrue
            $persistedActivationResults.total_count | Should -Be 30
            @($persistedActivationResults.sample).Count | Should -Be 20
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

            $reset = Invoke-ParsecCoreIngredientOperation -Name 'display.persist-topology' -Operation 'reset' -Arguments @{
                snapshot_name = 'topology-standalone'
            } -StateRoot $stateRoot

            $verify = Invoke-ParsecCoreIngredientOperation -Name 'display.persist-topology' -Operation 'verify' -Arguments @{
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

        It 'passes persisted apply output into token-based reset execution' {
            $stateRoot = Join-Path $TestDrive 'process-start-token-reset'
            $tokenId = 'process-start-token'

            $tokenDocument = @{
                token_id = $tokenId
                ingredient_name = 'process.start'
                requested_name = 'process.start'
                requested_arguments = @{
                    file_path = 'C:\Program Files\PowerShell\7\pwsh.exe'
                    arguments = @('-NoProfile', '-Command', 'Start-Sleep -Seconds 10')
                }
                resolved_target_identity = @{}
                captured_state = @{
                    is_running = $false
                }
                apply_result = @{
                    Outputs = @{
                        process_id = 4242
                        process_name = 'pwsh'
                        file_path = 'C:\Program Files\PowerShell\7\pwsh.exe'
                    }
                }
                readiness_result = $null
                verify_result = $null
                reset_result = $null
                reset_status = 'Available'
                created_at = [DateTimeOffset]::UtcNow.ToString('o')
                updated_at = [DateTimeOffset]::UtcNow.ToString('o')
            }
            $null = Save-ParsecIngredientTokenDocument -TokenDocument $tokenDocument -StateRoot $stateRoot

            Mock Get-Process {
                [pscustomobject]@{
                    Id = 4242
                    ProcessName = 'pwsh'
                }
            } -ParameterFilter { $Id -eq 4242 }
            Mock Stop-Process {} -ParameterFilter { $Id -eq 4242 }

            $reset = Invoke-ParsecIngredientCommandInternal -Name 'process.start' -Operation 'reset' -TokenId $tokenId -StateRoot $stateRoot

            $reset.status | Should -Be 'Succeeded'
            Should -Invoke Get-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 4242 }
            Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 4242 }
        }
    }
}
