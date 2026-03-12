function Initialize-ParsecIngredientTestEnvironment {
    $script:ParsecPersonalizationAdapter = @{
        GetThemeState = {
            return [ordered]@{
                mode        = 'Dark'
                app_mode    = 'Dark'
                system_mode = 'Dark'
            }
        }
        SetThemeState = {
            param($Arguments)

            $themeState = if ($Arguments.ContainsKey('theme_state')) {
                $Arguments.theme_state
            }
            else {
                $mode = if ($Arguments.ContainsKey('mode')) { $Arguments.mode } else { 'Custom' }
                $appMode = if ($Arguments.ContainsKey('app_mode')) { $Arguments.app_mode } elseif ($mode -in @('Dark', 'Light')) { $mode } else { 'Dark' }
                $systemMode = if ($Arguments.ContainsKey('system_mode')) { $Arguments.system_mode } elseif ($mode -in @('Dark', 'Light')) { $mode } else { 'Dark' }
                [ordered]@{
                    mode        = $mode
                    app_mode    = $appMode
                    system_mode = $systemMode
                }
            }

            New-ParsecResult -Status 'Succeeded' -Message 'theme' -Observed $themeState -Outputs @{ theme_state = $themeState }
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
                captured_at      = [DateTimeOffset]::UtcNow.ToString('o')
                computer_name    = 'TESTHOST'
                display_backend  = 'TestAdapter'
                monitor_identity = 'device_name'
                monitors         = @(
                    [ordered]@{
                        device_name  = '\\.\DISPLAY1'
                        is_primary   = $true
                        enabled      = $true
                        bounds       = [ordered]@{ x = 0; y = 0; width = 1920; height = 1080 }
                        working_area = [ordered]@{ x = 0; y = 0; width = 1920; height = 1040 }
                        orientation  = 'Landscape'
                        display      = [ordered]@{
                            width              = 1920
                            height             = 1080
                            bits_per_pel       = 32
                            refresh_rate_hz    = 60
                            effective_dpi_x    = 144
                            effective_dpi_y    = 144
                            scale_percent      = 150
                            text_scale_percent = 130
                        }
                        identity     = [ordered]@{
                            scheme              = 'adapter_id+target_id'
                            adapter_id          = '00000000:00000001'
                            source_id           = 0
                            target_id           = 1
                            source_name         = '\\.\DISPLAY1'
                            monitor_device_path = '\\?\DISPLAY#PRIMARY'
                        }
                        topology     = [ordered]@{
                            is_active           = $true
                            target_available    = $true
                            path_flags          = 1
                            source_status_flags = 0
                            target_status_flags = 0
                            output_technology   = 0
                            scaling_mode        = 0
                            scan_line_ordering  = 0
                            source_mode         = [ordered]@{
                                available    = $true
                                width        = 1920
                                height       = 1080
                                position_x   = 0
                                position_y   = 0
                                pixel_format = 0
                            }
                            target_mode         = [ordered]@{
                                available  = $true
                                width      = 1920
                                height     = 1080
                                pixel_rate = 0
                            }
                        }
                    }
                )
                scaling          = [ordered]@{
                    status             = 'Captured'
                    text_scale_percent = 130
                    monitors           = @(
                        [ordered]@{
                            device_name        = '\\.\DISPLAY1'
                            scale_percent      = 150
                            effective_dpi_x    = 144
                            effective_dpi_y    = 144
                            text_scale_percent = 130
                        }
                    )
                }
                topology         = [ordered]@{
                    query_mode = 'QDC_ALL_PATHS'
                    path_count = 1
                    paths      = @(
                        [ordered]@{
                            adapter_id          = '00000000:00000001'
                            source_id           = 0
                            target_id           = 1
                            source_name         = '\\.\DISPLAY1'
                            friendly_name       = 'Primary Panel'
                            monitor_device_path = '\\?\DISPLAY#PRIMARY'
                            is_active           = $true
                            target_available    = $true
                        }
                    )
                }
                font_scaling     = [ordered]@{
                    text_scale_percent = 130
                }
                theme            = [ordered]@{
                    mode        = 'Dark'
                    app_mode    = 'Dark'
                    system_mode = 'Dark'
                }
            }
        }
        SetEnabled     = { param($Arguments) New-ParsecResult -Status 'Succeeded' -Message 'enabled' -Requested $Arguments }
        SetPrimary     = { param($Arguments) New-ParsecResult -Status 'Succeeded' -Message 'primary' -Requested $Arguments }
        SetResolution  = { param($Arguments) New-ParsecResult -Status 'Succeeded' -Message 'resolution' -Requested $Arguments }
        SetOrientation = { param($Arguments) New-ParsecResult -Status 'Succeeded' -Message 'orientation' -Requested $Arguments }
        SetScaling     = { param($Arguments) New-ParsecResult -Status 'Succeeded' -Message 'scaling' -Requested $Arguments }
    }
}
