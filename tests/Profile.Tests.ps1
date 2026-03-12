$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

Describe 'Snapshot workflow' {
    InModuleScope ParsecEventExecutor {
        BeforeAll {
            $script:ParsecPersonalizationAdapter = @{
                GetThemeState = {
                    return [ordered]@{
                        mode = 'Dark'
                        app_mode = 'Dark'
                        system_mode = 'Dark'
                    }
                }
                GetWallpaperState = {
                    return [ordered]@{
                        path = 'C:\wallpapers\profile-test.jpg'
                        wallpaper_style = '10'
                        tile_wallpaper = '0'
                        background_color = '0 0 0'
                    }
                }
                SetThemeState = {
                    param($Arguments)
                    $themeState = if ($Arguments.ContainsKey('theme_state')) { $Arguments.theme_state } else { [ordered]@{ mode = $Arguments.mode; app_mode = $Arguments.app_mode; system_mode = $Arguments.system_mode } }
                    New-ParsecResult -Status 'Succeeded' -Message 'theme' -Observed $themeState -Outputs @{ theme_state = $themeState }
                }
                SetWallpaperState = {
                    param($Arguments)
                    $wallpaperState = if ($Arguments.ContainsKey('wallpaper_state')) { $Arguments.wallpaper_state } else { [ordered]@{ path = $Arguments.path; wallpaper_style = $Arguments.wallpaper_style; tile_wallpaper = $Arguments.tile_wallpaper; background_color = $Arguments.background_color } }
                    New-ParsecResult -Status 'Succeeded' -Message 'wallpaper' -Observed $wallpaperState -Outputs @{ wallpaper_state = $wallpaperState }
                }
                SetTextScale = {
                    param($Arguments)
                    $value = if ($Arguments.ContainsKey('text_scale_percent')) { [int] $Arguments.text_scale_percent } else { [int] $Arguments.value }
                    New-ParsecResult -Status 'Succeeded' -Message 'text-scale' -Observed @{ text_scale_percent = $value } -Outputs @{ text_scale_percent = $value }
                }
            }

            $script:ParsecDisplayAdapter = @{
                GetObservedState = {
                    return [ordered]@{
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
                                identity = [ordered]@{
                                    scheme = 'adapter_id+target_id'
                                    adapter_id = '00000000:00000001'
                                    source_id = 0
                                    target_id = 1
                                    source_name = '\\.\DISPLAY1'
                                    monitor_device_path = '\\?\DISPLAY#PRIMARY'
                                }
                                topology = [ordered]@{
                                    is_active = $true
                                    target_available = $true
                                    path_flags = 1
                                    source_status_flags = 0
                                    target_status_flags = 0
                                    output_technology = 0
                                    scaling_mode = 0
                                    scan_line_ordering = 0
                                    source_mode = [ordered]@{
                                        available = $true
                                        width = 1920
                                        height = 1080
                                        position_x = 0
                                        position_y = 0
                                        pixel_format = 0
                                    }
                                    target_mode = [ordered]@{
                                        available = $true
                                        width = 1920
                                        height = 1080
                                        pixel_rate = 0
                                    }
                                }
                            }
                        )
                        topology = [ordered]@{
                            query_mode = 'QDC_ALL_PATHS'
                            path_count = 1
                            paths = @(
                                [ordered]@{
                                    adapter_id = '00000000:00000001'
                                    source_id = 0
                                    target_id = 1
                                    source_name = '\\.\DISPLAY1'
                                    friendly_name = 'Primary Panel'
                                    monitor_device_path = '\\?\DISPLAY#PRIMARY'
                                    is_active = $true
                                    target_available = $true
                                }
                            )
                        }
                        scaling = [ordered]@{ status = 'Unsupported' }
                        font_scaling = [ordered]@{ text_scale_percent = 130 }
                        theme = [ordered]@{ mode = 'Dark'; app_mode = 'Dark'; system_mode = 'Dark' }
                        wallpaper = [ordered]@{ path = 'C:\wallpapers\profile-test.jpg'; wallpaper_style = '10'; tile_wallpaper = '0'; background_color = '0 0 0' }
                    }
                }
                SetEnabled = { param($Arguments) New-ParsecResult -Status 'Succeeded' -Message 'enabled' -Requested $Arguments }
                SetPrimary = { param($Arguments) New-ParsecResult -Status 'Succeeded' -Message 'primary' -Requested $Arguments }
                SetResolution = { param($Arguments) New-ParsecResult -Status 'Succeeded' -Message 'resolution' -Requested $Arguments }
                SetOrientation = { param($Arguments) New-ParsecResult -Status 'Succeeded' -Message 'orientation' -Requested $Arguments }
                SetScaling = { param($Arguments) New-ParsecResult -Status 'Succeeded' -Message 'scaling' -Requested $Arguments }
            }
        }

        It 'captures a transient snapshot and verifies it against the observed state' {
            $stateRoot = Join-Path $TestDrive 'snapshot-state'
            $snapshot = Save-ParsecSnapshot -Name 'desktop-pre-parsec' -StateRoot $stateRoot -Confirm:$false
            $verification = Test-ParsecSnapshot -Name 'desktop-pre-parsec' -StateRoot $stateRoot

            $snapshot.name | Should -Be 'desktop-pre-parsec'
            $snapshot.display.topology.path_count | Should -Be 1
            $snapshot.display.monitors[0].Contains('identity') | Should -BeTrue
            $snapshot.display.monitors[0]['identity']['scheme'] | Should -Be 'adapter_id+target_id'
            $snapshot.display.font_scaling.text_scale_percent | Should -Be 130
            $snapshot.display.theme.mode | Should -Be 'Dark'
            $snapshot.display.wallpaper.path | Should -Be 'C:\wallpapers\profile-test.jpg'
            $verification.Status | Should -Be 'Succeeded'
        }

        It 'restores a captured snapshot through the display snapshot ingredient' {
            $stateRoot = Join-Path $TestDrive 'restore-state'
            Save-ParsecSnapshot -Name 'desktop-pre-parsec' -StateRoot $stateRoot -Confirm:$false | Out-Null

            $result = Invoke-ParsecIngredientOperation -Name 'display.snapshot' -Operation 'reset' -Arguments @{
                snapshot_name = 'desktop-pre-parsec'
            } -StateRoot $stateRoot -RunState @{}

            $result.Status | Should -Be 'Succeeded'
            $result.Outputs['snapshot_name'] | Should -Be 'desktop-pre-parsec'
        }
    }
}
