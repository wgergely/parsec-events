function Set-ParsecIngredientObservedResolution {
    param(
        [Parameter(Mandatory)]
        [int] $Width,

        [Parameter(Mandatory)]
        [int] $Height
    )

    $script:IngredientObservedState.monitors[0].bounds.width = $Width
    $script:IngredientObservedState.monitors[0].bounds.height = $Height
    $script:IngredientObservedState.monitors[0].working_area.width = $Width
    $script:IngredientObservedState.monitors[0].working_area.height = [Math]::Max($Height - 40, 0)
    $script:IngredientObservedState.monitors[0].display.width = $Width
    $script:IngredientObservedState.monitors[0].display.height = $Height
    $script:IngredientObservedState.monitors[0].topology.source_mode.width = $Width
    $script:IngredientObservedState.monitors[0].topology.source_mode.height = $Height
    $script:IngredientObservedState.monitors[0].topology.target_mode.width = $Width
    $script:IngredientObservedState.monitors[0].topology.target_mode.height = $Height
}

function Set-ParsecIngredientObservedPosition {
    param(
        [Parameter(Mandatory)]
        [int] $X,

        [Parameter(Mandatory)]
        [int] $Y
    )

    $script:IngredientObservedState.monitors[0].bounds.x = $X
    $script:IngredientObservedState.monitors[0].bounds.y = $Y
    $script:IngredientObservedState.monitors[0].working_area.x = $X
    $script:IngredientObservedState.monitors[0].working_area.y = $Y
    $script:IngredientObservedState.monitors[0].topology.source_mode.position_x = $X
    $script:IngredientObservedState.monitors[0].topology.source_mode.position_y = $Y
}

function Add-ParsecIngredientSupportedMode {
    param(
        [Parameter(Mandatory)]
        [int] $Width,

        [Parameter(Mandatory)]
        [int] $Height,

        [Parameter()]
        [int] $BitsPerPel = 32,

        [Parameter()]
        [int] $RefreshRateHz = 60,

        [Parameter()]
        [string] $Orientation = 'Landscape'
    )

    $existing = @(
        $script:IngredientSupportedModes | Where-Object {
            [int] $_.width -eq $Width -and
            [int] $_.height -eq $Height -and
            [int] $_.bits_per_pel -eq $BitsPerPel -and
            [int] $_.refresh_rate_hz -eq $RefreshRateHz
        }
    )
    if ($existing.Count -gt 0) {
        return
    }

    $script:IngredientSupportedModes += [ordered]@{
        width = $Width
        height = $Height
        bits_per_pel = $BitsPerPel
        refresh_rate_hz = $RefreshRateHz
        orientation = $Orientation
    }
}

function Initialize-ParsecIngredientTestEnvironment {
    $script:IngredientResolutionMutationEnabled = $true
    $script:IngredientResolutionObservationLagRemaining = 0
    $script:IngredientResolutionPendingResolution = $null
    $script:IngredientNvidiaAvailable = $true
    $script:IngredientNvidiaLibraryPath = 'C:\Windows\System32\nvapi64.dll'
    $script:IngredientNvidiaDisplayIds = @{
        '\\.\DISPLAY1' = [uint32] 101
    }
    $script:IngredientNvidiaCustomResolutions = @{
        '101' = @()
    }
    $script:IngredientNvidiaSupportedModeLagRemaining = 0
    $script:IngredientNvidiaPendingSupportedMode = $null
    $script:IngredientSupportedModes = @(
        [ordered]@{ width = 1280; height = 720; bits_per_pel = 32; refresh_rate_hz = 60; orientation = 'Landscape' },
        [ordered]@{ width = 1920; height = 1080; bits_per_pel = 32; refresh_rate_hz = 60; orientation = 'Landscape' }
    )
    $script:IngredientObservedState = [ordered]@{
        captured_at = [DateTimeOffset]::UtcNow.ToString('o')
        computer_name = 'TESTHOST'
        display_backend = 'TestAdapter'
        monitor_identity = 'adapter_id+target_id'
        monitors = @(
            [ordered]@{
                device_name = '\\.\DISPLAY1'
                source_name = '\\.\DISPLAY1'
                friendly_name = 'Primary Panel'
                is_primary = $true
                enabled = $true
                bounds = [ordered]@{ x = 0; y = 0; width = 1920; height = 1080 }
                working_area = [ordered]@{ x = 0; y = 0; width = 1920; height = 1040 }
                orientation = 'Landscape'
                display = [ordered]@{
                    width = 1920
                    height = 1080
                    bits_per_pel = 32
                    refresh_rate_hz = 60
                    effective_dpi_x = 144
                    effective_dpi_y = 144
                    scale_percent = 150
                    text_scale_percent = 130
                }
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
                monitor_device_path = '\\?\DISPLAY#PRIMARY'
            }
        )
        scaling = [ordered]@{
            status = 'Captured'
            ui_scale_percent = 150
            text_scale_percent = 130
            monitors = @(
                [ordered]@{
                    device_name = '\\.\DISPLAY1'
                    scale_percent = 150
                    effective_dpi_x = 144
                    effective_dpi_y = 144
                    text_scale_percent = 130
                }
            )
        }
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
        font_scaling = [ordered]@{
            text_scale_percent = 130
        }
        theme = [ordered]@{
            mode = 'Dark'
            app_mode = 'Dark'
            system_mode = 'Dark'
        }
    }

    $script:ParsecPersonalizationAdapter = @{
        GetThemeState = {
            return ConvertTo-ParsecPlainObject -InputObject $script:IngredientObservedState.theme
        }
        SetThemeState = {
            param($Arguments)

            $themeState = if ($Arguments.ContainsKey('theme_state')) {
                ConvertTo-ParsecPlainObject -InputObject $Arguments.theme_state
            }
            else {
                $mode = if ($Arguments.ContainsKey('mode')) { $Arguments.mode } else { 'Custom' }
                $appMode = if ($Arguments.ContainsKey('app_mode')) { $Arguments.app_mode } elseif ($mode -in @('Dark', 'Light')) { $mode } else { 'Dark' }
                $systemMode = if ($Arguments.ContainsKey('system_mode')) { $Arguments.system_mode } elseif ($mode -in @('Dark', 'Light')) { $mode } else { 'Dark' }
                [ordered]@{
                    mode = $mode
                    app_mode = $appMode
                    system_mode = $systemMode
                }
            }

            $script:IngredientObservedState.theme = $themeState
            New-ParsecResult -Status 'Succeeded' -Message 'theme' -Observed $themeState -Outputs @{ theme_state = $themeState }
        }
        SetTextScale = {
            param($Arguments)

            $value = if ($Arguments.ContainsKey('text_scale_percent')) { [int] $Arguments.text_scale_percent } else { [int] $Arguments.value }
            $script:IngredientObservedState.font_scaling.text_scale_percent = $value
            $script:IngredientObservedState.scaling.text_scale_percent = $value
            $script:IngredientObservedState.scaling.monitors[0].text_scale_percent = $value
            $script:IngredientObservedState.monitors[0].display.text_scale_percent = $value
            New-ParsecResult -Status 'Succeeded' -Message 'text-scale' -Observed @{ text_scale_percent = $value } -Outputs @{ text_scale_percent = $value }
        }
    }

    $script:ParsecDisplayAdapter = @{
        GetObservedState = {
            if ($null -ne $script:IngredientResolutionPendingResolution) {
                if ($script:IngredientResolutionObservationLagRemaining -gt 0) {
                    $script:IngredientResolutionObservationLagRemaining--
                }
                else {
                    Set-ParsecIngredientObservedResolution -Width ([int] $script:IngredientResolutionPendingResolution.width) -Height ([int] $script:IngredientResolutionPendingResolution.height)
                    $script:IngredientResolutionPendingResolution = $null
                }
            }

            $script:IngredientObservedState.captured_at = [DateTimeOffset]::UtcNow.ToString('o')
            return ConvertTo-ParsecPlainObject -InputObject $script:IngredientObservedState
        }
        GetSupportedModes = {
            param($Arguments)

            if ($null -ne $script:IngredientNvidiaPendingSupportedMode) {
                if ($script:IngredientNvidiaSupportedModeLagRemaining -gt 0) {
                    $script:IngredientNvidiaSupportedModeLagRemaining--
                }
                else {
                    Add-ParsecIngredientSupportedMode `
                        -Width ([int] $script:IngredientNvidiaPendingSupportedMode.width) `
                        -Height ([int] $script:IngredientNvidiaPendingSupportedMode.height) `
                        -BitsPerPel ([int] $script:IngredientNvidiaPendingSupportedMode.bits_per_pel) `
                        -RefreshRateHz ([int] $script:IngredientNvidiaPendingSupportedMode.refresh_rate_hz)
                    $script:IngredientNvidiaPendingSupportedMode = $null
                }
            }

            return @($script:IngredientSupportedModes | ForEach-Object { ConvertTo-ParsecPlainObject -InputObject $_ })
        }
        SetEnabled = {
            param($Arguments)
            $script:IngredientObservedState.monitors[0].enabled = [bool] $Arguments.enabled
            if ($Arguments.ContainsKey('bounds') -and $Arguments.bounds -is [System.Collections.IDictionary]) {
                if ($Arguments.bounds.Contains('x')) {
                    Set-ParsecIngredientObservedPosition -X ([int] $Arguments.bounds.x) -Y ([int] $Arguments.bounds.y)
                }

                if ($Arguments.bounds.Contains('width') -and $Arguments.bounds.Contains('height') -and $Arguments.enabled) {
                    Set-ParsecIngredientObservedResolution -Width ([int] $Arguments.bounds.width) -Height ([int] $Arguments.bounds.height)
                }
            }

            New-ParsecResult -Status 'Succeeded' -Message 'enabled' -Requested $Arguments
        }
        SetPrimary = {
            param($Arguments)
            $script:IngredientObservedState.monitors[0].is_primary = $true
            New-ParsecResult -Status 'Succeeded' -Message 'primary' -Requested $Arguments
        }
        SetResolution = {
            param($Arguments)
            if ($script:IngredientResolutionMutationEnabled) {
                $width = [int] $Arguments.width
                $height = [int] $Arguments.height
                if ($script:IngredientResolutionObservationLagRemaining -gt 0) {
                    $script:IngredientResolutionPendingResolution = [ordered]@{
                        width = $width
                        height = $height
                    }
                }
                else {
                    Set-ParsecIngredientObservedResolution -Width $width -Height $height
                }
            }

            New-ParsecResult -Status 'Succeeded' -Message 'resolution' -Requested $Arguments
        }
        SetOrientation = {
            param($Arguments)
            $script:IngredientObservedState.monitors[0].orientation = [string] $Arguments.orientation
            New-ParsecResult -Status 'Succeeded' -Message 'orientation' -Requested $Arguments
        }
        SetScaling = {
            param($Arguments)
            if ($Arguments.ContainsKey('ui_scale_percent')) {
                $value = [int] $Arguments.ui_scale_percent
                $script:IngredientObservedState.scaling.ui_scale_percent = $value
                $script:IngredientObservedState.monitors[0].display.scale_percent = $value
                $script:IngredientObservedState.scaling.monitors[0].scale_percent = $value
            }
            elseif ($Arguments.ContainsKey('text_scale_percent')) {
                $value = [int] $Arguments.text_scale_percent
                $script:IngredientObservedState.font_scaling.text_scale_percent = $value
                $script:IngredientObservedState.scaling.text_scale_percent = $value
                $script:IngredientObservedState.scaling.monitors[0].text_scale_percent = $value
                $script:IngredientObservedState.monitors[0].display.text_scale_percent = $value
            }

            New-ParsecResult -Status 'Succeeded' -Message 'scaling' -Requested $Arguments
        }
    }

    $script:ParsecNvidiaAdapter = @{
        GetAvailability = {
            return [ordered]@{
                available = [bool] $script:IngredientNvidiaAvailable
                library_path = if ($script:IngredientNvidiaAvailable) { $script:IngredientNvidiaLibraryPath } else { $null }
                backend = 'TestNvidiaAdapter'
                message = if ($script:IngredientNvidiaAvailable) { 'NVIDIA adapter available.' } else { 'NVIDIA adapter unavailable.' }
                errors = if ($script:IngredientNvidiaAvailable) { @() } else { @('CapabilityUnavailable') }
            }
        }
        ResolveDisplayTarget = {
            param($Arguments)

            if (-not $script:IngredientNvidiaAvailable) {
                throw 'NVIDIA adapter unavailable.'
            }

            $deviceName = [string] $Arguments.device_name
            if (-not $script:IngredientNvidiaDisplayIds.ContainsKey($deviceName)) {
                throw "No NVIDIA display target was registered for '$deviceName'."
            }

            [ordered]@{
                device_name = $deviceName
                normalized_display_name = $deviceName
                display_id = [uint32] $script:IngredientNvidiaDisplayIds[$deviceName]
                library_path = $script:IngredientNvidiaLibraryPath
                backend = 'TestNvidiaAdapter'
            }
        }
        GetCustomResolutions = {
            param($Arguments)

            $displayIdKey = [string] ([uint32] $Arguments.display_id)
            if (-not $script:IngredientNvidiaCustomResolutions.ContainsKey($displayIdKey)) {
                return @()
            }

            return @($script:IngredientNvidiaCustomResolutions[$displayIdKey] | ForEach-Object { ConvertTo-ParsecPlainObject -InputObject $_ })
        }
        AddCustomResolution = {
            param($Arguments)

            if (-not $script:IngredientNvidiaAvailable) {
                return New-ParsecResult -Status 'Failed' -Message 'NVIDIA adapter unavailable.' -Requested $Arguments -Errors @('CapabilityUnavailable')
            }

            $displayIdKey = [string] ([uint32] $Arguments.display_id)
            if (-not $script:IngredientNvidiaCustomResolutions.ContainsKey($displayIdKey)) {
                $script:IngredientNvidiaCustomResolutions[$displayIdKey] = @()
            }

            $customResolution = [ordered]@{
                width = [int] $Arguments.width
                height = [int] $Arguments.height
                depth = if ($Arguments.ContainsKey('bits_per_pel')) { [int] $Arguments.bits_per_pel } else { 32 }
                refresh_rate_hz = if ($Arguments.ContainsKey('refresh_rate_hz')) { [double] $Arguments.refresh_rate_hz } else { 60.0 }
                color_format = 0
                timing_status = 0
                hardware_mode_set_only = $false
            }

            $existing = @(
                $script:IngredientNvidiaCustomResolutions[$displayIdKey] | Where-Object {
                    [int] $_.width -eq [int] $customResolution.width -and
                    [int] $_.height -eq [int] $customResolution.height
                }
            )
            if ($existing.Count -eq 0) {
                $script:IngredientNvidiaCustomResolutions[$displayIdKey] += $customResolution
            }

            Set-ParsecIngredientObservedPosition -X 640 -Y 360
            Set-ParsecIngredientObservedResolution -Width ([int] $customResolution.width) -Height ([int] $customResolution.height)
            $script:IngredientObservedState.monitors[0].display.refresh_rate_hz = [int] [Math]::Round([double] $customResolution.refresh_rate_hz)

            $script:IngredientNvidiaPendingSupportedMode = [ordered]@{
                width = [int] $customResolution.width
                height = [int] $customResolution.height
                bits_per_pel = [int] $customResolution.depth
                refresh_rate_hz = [int] [Math]::Round([double] $customResolution.refresh_rate_hz)
            }
            if ($script:IngredientNvidiaSupportedModeLagRemaining -le 0) {
                Add-ParsecIngredientSupportedMode `
                    -Width ([int] $customResolution.width) `
                    -Height ([int] $customResolution.height) `
                    -BitsPerPel ([int] $customResolution.depth) `
                    -RefreshRateHz ([int] [Math]::Round([double] $customResolution.refresh_rate_hz))
                $script:IngredientNvidiaPendingSupportedMode = $null
            }

            New-ParsecResult -Status 'Succeeded' -Message 'nvidia-custom-resolution' -Requested $Arguments -Outputs @{
                display_id = [uint32] $Arguments.display_id
                width = [int] $customResolution.width
                height = [int] $customResolution.height
                refresh_rate_hz = [double] $customResolution.refresh_rate_hz
                bits_per_pel = [int] $customResolution.depth
            }
        }
    }
}
