$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

Describe 'Executor state entrypoints' {
    It 'returns verify-only state without mutating recipes' {
        $stateRoot = Join-Path $TestDrive 'verify-only'
        $result = Start-ParsecExecutor -EventName VerifyOnly -StateRoot $stateRoot -Confirm:$false

        $result.event_name | Should -Be 'VerifyOnly'
        $result.state.transition_phase | Should -Be 'Idle'
    }

    InModuleScope ParsecEventExecutor {
        BeforeAll {
            $script:ExecutorThemeState = [ordered]@{
                mode = 'Light'
                app_mode = 'Light'
                system_mode = 'Light'
            }
            $script:ExecutorTextScalePercent = 100
            $script:ExecutorUiScalePercent = 100
            $script:ExecutorWallpaperState = [ordered]@{
                path = 'C:\wallpapers\executor-test.jpg'
                wallpaper_style = '10'
                tile_wallpaper = '0'
                background_color = '0 0 0'
            }
            $script:ExecutorObservedState = [ordered]@{
                captured_at = [DateTimeOffset]::UtcNow.ToString('o')
                computer_name = 'TESTHOST'
                display_backend = 'TestAdapter'
                monitor_identity = 'device_name'
                monitors = @(
                    [ordered]@{
                        device_name = '\\.\DISPLAY1'
                        is_primary = $true
                        enabled = $true
                        bounds = [ordered]@{ x = 0; y = 0; width = 1920; height = 1080 }
                        working_area = [ordered]@{ x = 0; y = 0; width = 1920; height = 1040 }
                        orientation = 'Landscape'
                        display = [ordered]@{
                            width = 1920
                            height = 1080
                            scale_percent = 100
                            text_scale_percent = 100
                        }
                    }
                )
                scaling = [ordered]@{ status = 'Captured'; ui_scale_percent = 100; text_scale_percent = 100; monitors = @() }
                font_scaling = [ordered]@{ text_scale_percent = 100 }
                theme = $script:ExecutorThemeState
                wallpaper = $script:ExecutorWallpaperState
            }

            $script:ParsecPersonalizationAdapter = @{
                GetThemeState = {
                    return $script:ExecutorThemeState
                }
                GetWallpaperState = {
                    return $script:ExecutorWallpaperState
                }
                SetThemeState = {
                    param($Arguments)
                    $themeState = if ($Arguments.ContainsKey('theme_state')) {
                        $Arguments.theme_state
                    }
                    else {
                        $mode = if ($Arguments.ContainsKey('mode')) { [string] $Arguments.mode } else { 'Custom' }
                        $appMode = if ($Arguments.ContainsKey('app_mode')) { [string] $Arguments.app_mode } elseif ($mode -in @('Dark', 'Light')) { $mode } else { 'Light' }
                        $systemMode = if ($Arguments.ContainsKey('system_mode')) { [string] $Arguments.system_mode } elseif ($mode -in @('Dark', 'Light')) { $mode } else { 'Light' }
                        [ordered]@{
                            mode = $mode
                            app_mode = $appMode
                            system_mode = $systemMode
                        }
                    }
                    $script:ExecutorThemeState = $themeState
                    $script:ExecutorObservedState.theme = $themeState
                    New-ParsecResult -Status 'Succeeded' -Message 'theme' -Observed $themeState -Outputs @{ theme_state = $themeState }
                }
                SetWallpaperState = {
                    param($Arguments)
                    $wallpaperState = if ($Arguments.ContainsKey('wallpaper_state')) {
                        $Arguments.wallpaper_state
                    }
                    else {
                        [ordered]@{
                            path = [string] $Arguments.path
                            wallpaper_style = [string] $Arguments.wallpaper_style
                            tile_wallpaper = [string] $Arguments.tile_wallpaper
                            background_color = [string] $Arguments.background_color
                        }
                    }
                    $script:ExecutorWallpaperState = $wallpaperState
                    $script:ExecutorObservedState.wallpaper = $wallpaperState
                    New-ParsecResult -Status 'Succeeded' -Message 'wallpaper' -Observed $wallpaperState -Outputs @{ wallpaper_state = $wallpaperState }
                }
                SetUiScale = {
                    param($Arguments)
                    $value = if ($Arguments.ContainsKey('ui_scale_percent')) { [int] $Arguments.ui_scale_percent } elseif ($Arguments.ContainsKey('scale_percent')) { [int] $Arguments.scale_percent } else { [int] $Arguments.value }
                    $script:ExecutorUiScalePercent = $value
                    $script:ExecutorObservedState.scaling.ui_scale_percent = $value
                    $script:ExecutorObservedState.monitors[0].display.scale_percent = $value
                    New-ParsecResult -Status 'Succeeded' -Message 'ui-scale' -Observed @{ ui_scale_percent = $value } -Outputs @{ ui_scale_percent = $value; requires_signout = $true }
                }
                SetTextScale = {
                    param($Arguments)
                    $value = if ($Arguments.ContainsKey('text_scale_percent')) { [int] $Arguments.text_scale_percent } else { [int] $Arguments.value }
                    $script:ExecutorTextScalePercent = $value
                    $script:ExecutorObservedState.font_scaling.text_scale_percent = $value
                    $script:ExecutorObservedState.scaling.text_scale_percent = $value
                    $script:ExecutorObservedState.monitors[0].display.text_scale_percent = $value
                    New-ParsecResult -Status 'Succeeded' -Message 'text-scale' -Observed @{ text_scale_percent = $value } -Outputs @{ text_scale_percent = $value }
                }
            }

            $script:ParsecDisplayAdapter = @{
                GetObservedState = {
                    $script:ExecutorObservedState.captured_at = [DateTimeOffset]::UtcNow.ToString('o')
                    return $script:ExecutorObservedState
                }
                GetSupportedModes = {
                    @(
                        [ordered]@{ width = 1920; height = 1080; bits_per_pel = 32; refresh_rate_hz = 60; orientation = 'Landscape' },
                        [ordered]@{ width = 2000; height = 3000; bits_per_pel = 32; refresh_rate_hz = 60; orientation = 'Portrait' }
                    )
                }
                SetEnabled = {
                    param($Arguments)
                    $monitor = $script:ExecutorObservedState.monitors[0]
                    $monitor.enabled = [bool] $Arguments.enabled
                    New-ParsecResult -Status 'Succeeded' -Message 'enabled' -Requested $Arguments
                }
                SetPrimary = {
                    param($Arguments)
                    $script:ExecutorObservedState.monitors[0].is_primary = $true
                    New-ParsecResult -Status 'Succeeded' -Message 'primary' -Requested $Arguments
                }
                SetResolution = {
                    param($Arguments)
                    $monitor = $script:ExecutorObservedState.monitors[0]
                    $monitor.bounds.width = [int] $Arguments.width
                    $monitor.bounds.height = [int] $Arguments.height
                    $monitor.display.width = [int] $Arguments.width
                    $monitor.display.height = [int] $Arguments.height
                    New-ParsecResult -Status 'Succeeded' -Message 'resolution' -Requested $Arguments
                }
                SetOrientation = {
                    param($Arguments)
                    $script:ExecutorObservedState.monitors[0].orientation = [string] $Arguments.orientation
                    New-ParsecResult -Status 'Succeeded' -Message 'orientation' -Requested $Arguments
                }
                SetScaling = {
                    param($Arguments)
                    if ($Arguments.ContainsKey('ui_scale_percent')) {
                        $script:ExecutorUiScalePercent = [int] $Arguments.ui_scale_percent
                        $script:ExecutorObservedState.scaling.ui_scale_percent = [int] $Arguments.ui_scale_percent
                        $script:ExecutorObservedState.monitors[0].display.scale_percent = [int] $Arguments.ui_scale_percent
                    }
                    elseif ($Arguments.ContainsKey('text_scale_percent')) {
                        $script:ExecutorTextScalePercent = [int] $Arguments.text_scale_percent
                        $script:ExecutorObservedState.font_scaling.text_scale_percent = [int] $Arguments.text_scale_percent
                        $script:ExecutorObservedState.scaling.text_scale_percent = [int] $Arguments.text_scale_percent
                        $script:ExecutorObservedState.monitors[0].display.text_scale_percent = [int] $Arguments.text_scale_percent
                    }
                    New-ParsecResult -Status 'Succeeded' -Message 'scaling' -Requested $Arguments
                }
            }

            Set-ParsecModuleVariableValue -Name 'ParsecPersonalizationAdapter' -Value $script:ParsecPersonalizationAdapter | Out-Null
            Set-ParsecModuleVariableValue -Name 'ParsecDisplayAdapter' -Value $script:ParsecDisplayAdapter | Out-Null
        }

        It 'captures a transient snapshot when running a connect recipe' {
            $stateRoot = Join-Path $TestDrive 'test-connect'
            $connectPath = Join-Path $PSScriptRoot 'fixtures\recipes\dev-connect.toml'
            $result = Invoke-ParsecRecipe -NameOrPath $connectPath -StateRoot $stateRoot -Confirm:$false
            $state = Get-ParsecExecutorStateDocument -StateRoot $stateRoot

            $result.recipe_name | Should -Be 'dev-connect'
            $result.terminal_status | Should -Be 'Succeeded'
            $result.step_results[0].ingredient | Should -Be 'display.snapshot'
            $result.step_results[0].operation | Should -Be 'capture'
            $state.active_snapshot | Should -Be 'pre-connect'
        }

        It 'restores the active snapshot when running a disconnect recipe' {
            $stateRoot = Join-Path $TestDrive 'test-disconnect'
            $connectPath = Join-Path $PSScriptRoot 'fixtures\recipes\dev-connect.toml'
            $disconnectPath = Join-Path $PSScriptRoot 'fixtures\recipes\dev-disconnect.toml'
            Invoke-ParsecRecipe -NameOrPath $connectPath -StateRoot $stateRoot -Confirm:$false | Out-Null

            $result = Invoke-ParsecRecipe -NameOrPath $disconnectPath -StateRoot $stateRoot -Confirm:$false

            $result.recipe_name | Should -Be 'dev-disconnect'
            $result.terminal_status | Should -Be 'Succeeded'
            $result.step_results[0].operation | Should -Be 'reset'
        }

        It 'reports persistence drift during reconciliation when the active snapshot is missing' {
            $stateRoot = Join-Path $TestDrive 'reconcile-missing-snapshot'
            $connectPath = Join-Path $PSScriptRoot 'fixtures\recipes\dev-connect.toml'
            Invoke-ParsecRecipe -NameOrPath $connectPath -StateRoot $stateRoot -Confirm:$false | Out-Null
            Remove-Item -LiteralPath (Join-Path $stateRoot 'snapshots\pre-connect.json') -Force

            $result = Start-ParsecExecutor -EventName Reconcile -StateRoot $stateRoot -Confirm:$false

            $result.status | Should -Be 'RecoverableDrift'
            $result.recoverable | Should -BeTrue
            $result.issues.Count | Should -BeGreaterThan 0
            ($result.issues -join ' ') | Should -Match 'Active snapshot'
            $result.recovery_candidate.last_run_id | Should -Not -BeNullOrEmpty
        }

        It 'repairs executor state from the event journal' {
            $stateRoot = Join-Path $TestDrive 'repair-from-events'
            $connectPath = Join-Path $PSScriptRoot 'fixtures\recipes\dev-connect.toml'
            Invoke-ParsecRecipe -NameOrPath $connectPath -StateRoot $stateRoot -Confirm:$false | Out-Null

            $stateDocument = Get-Content -LiteralPath (Join-Path $stateRoot 'executor-state.json') -Raw | ConvertFrom-Json -Depth 100
            $stateDocument.payload.active_snapshot = $null
            $stateDocument.payload.transition_phase = 'Running'
            $stateDocument.payload.last_run_id = 'corrupt-run-id'
            $stateDocument | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $stateRoot 'executor-state.json') -Encoding UTF8

            $before = Start-ParsecExecutor -EventName Reconcile -StateRoot $stateRoot -Confirm:$false
            $repair = Repair-ParsecExecutorState -StateRoot $stateRoot -Confirm:$false
            $after = Start-ParsecExecutor -EventName Reconcile -StateRoot $stateRoot -Confirm:$false

            $before.status | Should -Be 'RecoverableDrift'
            $repair.status | Should -Be 'Recovered'
            $repair.repaired | Should -BeTrue
            $after.status | Should -Be 'Converged'
            $after.active_snapshot | Should -Be 'pre-connect'
        }

        It 'preserves scalar identifiers when reading event documents' {
            $stateRoot = Join-Path $TestDrive 'event-scalar-identifiers'
            $connectPath = Join-Path $PSScriptRoot 'fixtures\recipes\dev-connect.toml'
            Invoke-ParsecRecipe -NameOrPath $connectPath -StateRoot $stateRoot -Confirm:$false | Out-Null

            $events = @(Get-ParsecEventDocument -StateRoot $stateRoot)
            $candidate = Get-ParsecRecoveryCandidateFromEvent -StateRoot $stateRoot

            $events.Count | Should -BeGreaterThan 0
            $events[0].payload.run_id | Should -BeOfType ([string])
            $events[0].payload.transition_id | Should -BeOfType ([string])
            $candidate.last_run_id | Should -BeOfType ([string])
            $candidate.transition_id | Should -BeOfType ([string])
        }
    }
}
