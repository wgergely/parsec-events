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

function Get-ParsecIngredientObservedMonitorByDeviceName {
    param(
        [Parameter(Mandatory)]
        [string] $DeviceName
    )

    return @($script:IngredientObservedState.monitors) | Where-Object { [string] $_.device_name -eq $DeviceName } | Select-Object -First 1
}

function Enable-ParsecIngredientDualMonitorEnvironment {
    $secondaryMonitor = [ordered]@{
        device_name = '\\.\DISPLAY2'
        source_name = '\\.\DISPLAY2'
        friendly_name = 'Secondary Panel'
        is_primary = $false
        enabled = $true
        bounds = [ordered]@{ x = -1600; y = 0; width = 1600; height = 900 }
        working_area = [ordered]@{ x = -1600; y = 0; width = 1600; height = 860 }
        orientation = 'Landscape'
        display = [ordered]@{
            width = 1600
            height = 900
            bits_per_pel = 32
            refresh_rate_hz = 60
            effective_dpi_x = 96
            effective_dpi_y = 96
            scale_percent = 100
            text_scale_percent = 130
        }
        identity = [ordered]@{
            scheme = 'adapter_id+target_id'
            adapter_id = '00000000:00000001'
            source_id = 1
            target_id = 2
            source_name = '\\.\DISPLAY2'
            monitor_device_path = '\\?\DISPLAY#SECONDARY'
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
                width = 1600
                height = 900
                position_x = -1600
                position_y = 0
                pixel_format = 0
            }
            target_mode = [ordered]@{
                available = $true
                width = 1600
                height = 900
                pixel_rate = 0
            }
        }
        monitor_device_path = '\\?\DISPLAY#SECONDARY'
        target_available = $true
    }

    $script:IngredientObservedState.monitors += , $secondaryMonitor
    $script:IngredientObservedState.scaling.monitors += , [ordered]@{
        device_name = '\\.\DISPLAY2'
        scale_percent = 100
        effective_dpi_x = 96
        effective_dpi_y = 96
        text_scale_percent = 130
    }
    $script:IngredientObservedState.topology.path_count = 2
    $script:IngredientObservedState.topology.paths += , [ordered]@{
        adapter_id = '00000000:00000001'
        source_id = 1
        target_id = 2
        source_name = '\\.\DISPLAY2'
        friendly_name = 'Secondary Panel'
        monitor_device_path = '\\?\DISPLAY#SECONDARY'
        is_active = $true
        target_available = $true
    }
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
    $script:IngredientOrientationMutationEnabled = $true
    $script:IngredientOrientationObservationLagRemaining = 0
    $script:IngredientOrientationPendingOrientation = $null
    $script:IngredientUiScaleObservationLagRemaining = 0
    $script:IngredientUiScalePendingValue = $null
    $script:IngredientUiScaleMinimum = $null
    $script:IngredientUiScaleMaximum = $null
    $script:IngredientTextScaleObservationLagRemaining = 0
    $script:IngredientTextScalePendingValue = $null
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
    $script:IngredientWindowActivationLog = @()
    $script:IngredientWindowActivationDeniedHandles = @()
    $script:IngredientWindowForegroundHandle = 101
    $script:IngredientAltTabHandles = @([int64] 101, [int64] 102)
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
            is_on_input_desktop = $true
            is_on_current_virtual_desktop = $true
            extended_style = 0
            width = 1440
            height = 900
        },
        [ordered]@{
            handle = [int64] 102
            owner_handle = [int64] 0
            process_id = 1002
            process_name = 'chrome'
            title = 'Browser'
            class_name = 'Chrome_WidgetWin_1'
            is_visible = $true
            is_minimized = $false
            is_cloaked = $false
            is_shell_window = $false
            is_on_input_desktop = $true
            is_on_current_virtual_desktop = $true
            extended_style = 0
            width = 1280
            height = 720
        },
        [ordered]@{
            handle = [int64] 103
            owner_handle = [int64] 0
            process_id = 1003
            process_name = 'UtilityHost'
            title = 'Hidden Utility'
            class_name = 'ToolWindow'
            is_visible = $false
            is_minimized = $false
            is_cloaked = $false
            is_shell_window = $false
            is_on_input_desktop = $true
            is_on_current_virtual_desktop = $true
            extended_style = 0
            width = 320
            height = 120
        }
    )
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
        wallpaper = [ordered]@{
            path = 'C:\wallpapers\parsec-test.jpg'
            wallpaper_style = '10'
            tile_wallpaper = '0'
            background_color = '0 0 0'
        }
    }

    $script:ParsecPersonalizationAdapter = @{
        GetThemeState = {
            return ConvertTo-ParsecPlainObject -InputObject $script:IngredientObservedState.theme
        }
        GetWallpaperState = {
            return ConvertTo-ParsecPlainObject -InputObject $script:IngredientObservedState.wallpaper
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
        SetWallpaperState = {
            param($Arguments)

            $wallpaperState = if ($Arguments.ContainsKey('wallpaper_state')) {
                ConvertTo-ParsecPlainObject -InputObject $Arguments.wallpaper_state
            }
            else {
                [ordered]@{
                    path = if ($Arguments.ContainsKey('path')) { [string] $Arguments.path } else { '' }
                    wallpaper_style = if ($Arguments.ContainsKey('wallpaper_style')) { [string] $Arguments.wallpaper_style } else { '' }
                    tile_wallpaper = if ($Arguments.ContainsKey('tile_wallpaper')) { [string] $Arguments.tile_wallpaper } else { '' }
                    background_color = if ($Arguments.ContainsKey('background_color')) { [string] $Arguments.background_color } else { '' }
                }
            }

            $script:IngredientObservedState.wallpaper = $wallpaperState
            New-ParsecResult -Status 'Succeeded' -Message 'wallpaper' -Observed $wallpaperState -Outputs @{ wallpaper_state = $wallpaperState }
        }
        SetUiScale = {
            param($Arguments)

            $requestedValue = if ($Arguments.ContainsKey('ui_scale_percent')) { [int] $Arguments.ui_scale_percent } elseif ($Arguments.ContainsKey('scale_percent')) { [int] $Arguments.scale_percent } else { [int] $Arguments.value }
            $value = $requestedValue
            if ($null -ne $script:IngredientUiScaleMinimum -and $value -lt [int] $script:IngredientUiScaleMinimum) {
                $value = [int] $script:IngredientUiScaleMinimum
            }

            if ($null -ne $script:IngredientUiScaleMaximum -and $value -gt [int] $script:IngredientUiScaleMaximum) {
                $value = [int] $script:IngredientUiScaleMaximum
            }

            if ($script:IngredientUiScaleObservationLagRemaining -gt 0) {
                $script:IngredientUiScalePendingValue = $value
            }
            else {
                $script:IngredientObservedState.scaling.ui_scale_percent = $value
                $script:IngredientObservedState.scaling.monitors[0].scale_percent = $value
                $script:IngredientObservedState.monitors[0].display.scale_percent = $value
            }

            New-ParsecResult -Status 'Succeeded' -Message 'ui-scale' -Observed @{ ui_scale_percent = $value } -Outputs @{ requested_ui_scale_percent = $requestedValue; ui_scale_percent = $value; requires_signout = $true }
        }
        SetTextScale = {
            param($Arguments)

            $value = if ($Arguments.ContainsKey('text_scale_percent')) { [int] $Arguments.text_scale_percent } else { [int] $Arguments.value }
            if ($script:IngredientTextScaleObservationLagRemaining -gt 0) {
                $script:IngredientTextScalePendingValue = $value
            }
            else {
                $script:IngredientObservedState.font_scaling.text_scale_percent = $value
                $script:IngredientObservedState.scaling.text_scale_percent = $value
                $script:IngredientObservedState.scaling.monitors[0].text_scale_percent = $value
                $script:IngredientObservedState.monitors[0].display.text_scale_percent = $value
            }

            New-ParsecResult -Status 'Succeeded' -Message 'text-scale' -Observed @{ text_scale_percent = $value } -Outputs @{ text_scale_percent = $value }
        }
    }
    $global:ParsecPersonalizationAdapter = $script:ParsecPersonalizationAdapter

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

            if ($null -ne $script:IngredientOrientationPendingOrientation) {
                if ($script:IngredientOrientationObservationLagRemaining -gt 0) {
                    $script:IngredientOrientationObservationLagRemaining--
                }
                else {
                    $monitor = Get-ParsecIngredientObservedMonitorByDeviceName -DeviceName ([string] $script:IngredientOrientationPendingOrientation.device_name)
                    if ($null -ne $monitor) {
                        $monitor.orientation = [string] $script:IngredientOrientationPendingOrientation.orientation
                    }

                    $script:IngredientOrientationPendingOrientation = $null
                }
            }

            if ($null -ne $script:IngredientUiScalePendingValue) {
                if ($script:IngredientUiScaleObservationLagRemaining -gt 0) {
                    $script:IngredientUiScaleObservationLagRemaining--
                }
                else {
                    $value = [int] $script:IngredientUiScalePendingValue
                    $script:IngredientObservedState.scaling.ui_scale_percent = $value
                    $script:IngredientObservedState.scaling.monitors[0].scale_percent = $value
                    $script:IngredientObservedState.monitors[0].display.scale_percent = $value
                    $script:IngredientUiScalePendingValue = $null
                }
            }

            if ($null -ne $script:IngredientTextScalePendingValue) {
                if ($script:IngredientTextScaleObservationLagRemaining -gt 0) {
                    $script:IngredientTextScaleObservationLagRemaining--
                }
                else {
                    $value = [int] $script:IngredientTextScalePendingValue
                    $script:IngredientObservedState.font_scaling.text_scale_percent = $value
                    $script:IngredientObservedState.scaling.text_scale_percent = $value
                    $script:IngredientObservedState.scaling.monitors[0].text_scale_percent = $value
                    $script:IngredientObservedState.monitors[0].display.text_scale_percent = $value
                    $script:IngredientTextScalePendingValue = $null
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
            $monitor = Get-ParsecIngredientObservedMonitorByDeviceName -DeviceName ([string] $Arguments.device_name)
            if ($null -eq $monitor) {
                return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' not found." -Requested $Arguments -Errors @('MonitorNotFound')
            }

            $monitor.enabled = [bool] $Arguments.enabled
            $monitor.topology.is_active = [bool] $Arguments.enabled
            if ($Arguments.ContainsKey('bounds') -and $Arguments.bounds -is [System.Collections.IDictionary]) {
                if ($Arguments.bounds.Contains('x')) {
                    $monitor.bounds.x = $Arguments.bounds.x
                    $monitor.working_area.x = $Arguments.bounds.x
                    $monitor.topology.source_mode.position_x = $Arguments.bounds.x
                }

                if ($Arguments.bounds.Contains('y')) {
                    $monitor.bounds.y = $Arguments.bounds.y
                    $monitor.working_area.y = $Arguments.bounds.y
                    $monitor.topology.source_mode.position_y = $Arguments.bounds.y
                }

                if ($Arguments.bounds.Contains('width') -and $Arguments.bounds.Contains('height') -and $Arguments.enabled) {
                    $monitor.bounds.width = [int] $Arguments.bounds.width
                    $monitor.bounds.height = [int] $Arguments.bounds.height
                    $monitor.working_area.width = [int] $Arguments.bounds.width
                    $monitor.working_area.height = [Math]::Max([int] $Arguments.bounds.height - 40, 0)
                    $monitor.display.width = [int] $Arguments.bounds.width
                    $monitor.display.height = [int] $Arguments.bounds.height
                    $monitor.topology.source_mode.width = [int] $Arguments.bounds.width
                    $monitor.topology.source_mode.height = [int] $Arguments.bounds.height
                    $monitor.topology.target_mode.width = [int] $Arguments.bounds.width
                    $monitor.topology.target_mode.height = [int] $Arguments.bounds.height
                }
            }
            elseif (-not [bool] $Arguments.enabled) {
                $monitor.bounds.x = $null
                $monitor.bounds.y = $null
                $monitor.bounds.width = $null
                $monitor.bounds.height = $null
                $monitor.working_area.x = $null
                $monitor.working_area.y = $null
                $monitor.working_area.width = $null
                $monitor.working_area.height = $null
                $monitor.display.width = $null
                $monitor.display.height = $null
                $monitor.topology.source_mode.available = $false
                $monitor.topology.source_mode.width = $null
                $monitor.topology.source_mode.height = $null
                $monitor.topology.source_mode.position_x = $null
                $monitor.topology.source_mode.position_y = $null
                $monitor.topology.target_mode.available = $false
                $monitor.topology.target_mode.width = $null
                $monitor.topology.target_mode.height = $null
            }

            New-ParsecResult -Status 'Succeeded' -Message 'enabled' -Requested $Arguments
        }
        SetPrimary = {
            param($Arguments)
            foreach ($monitor in @($script:IngredientObservedState.monitors)) {
                $monitor.is_primary = $false
            }

            $monitor = Get-ParsecIngredientObservedMonitorByDeviceName -DeviceName ([string] $Arguments.device_name)
            if ($null -eq $monitor) {
                return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' not found." -Requested $Arguments -Errors @('MonitorNotFound')
            }

            $monitor.is_primary = $true
            if ($monitor.bounds -is [System.Collections.IDictionary]) {
                $monitor.bounds.x = 0
                $monitor.bounds.y = 0
                $monitor.working_area.x = 0
                $monitor.working_area.y = 0
                $monitor.topology.source_mode.position_x = 0
                $monitor.topology.source_mode.position_y = 0
            }

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
            $monitor = Get-ParsecIngredientObservedMonitorByDeviceName -DeviceName ([string] $Arguments.device_name)
            if ($null -eq $monitor) {
                return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' not found." -Requested $Arguments -Errors @('MonitorNotFound')
            }

            if ($script:IngredientOrientationMutationEnabled) {
                if ($script:IngredientOrientationObservationLagRemaining -gt 0) {
                    $script:IngredientOrientationPendingOrientation = [ordered]@{
                        device_name = [string] $Arguments.device_name
                        orientation = [string] $Arguments.orientation
                    }
                }
                else {
                    $monitor.orientation = [string] $Arguments.orientation
                }
            }

            New-ParsecResult -Status 'Succeeded' -Message 'orientation' -Requested $Arguments
        }
        SetScaling = {
            param($Arguments)
            if ($Arguments.ContainsKey('ui_scale_percent')) {
                $value = [int] $Arguments.ui_scale_percent
                if ($script:IngredientUiScaleObservationLagRemaining -gt 0) {
                    $script:IngredientUiScalePendingValue = $value
                }
                else {
                    $script:IngredientObservedState.scaling.ui_scale_percent = $value
                    $script:IngredientObservedState.monitors[0].display.scale_percent = $value
                    $script:IngredientObservedState.scaling.monitors[0].scale_percent = $value
                }
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
    $global:ParsecDisplayAdapter = $script:ParsecDisplayAdapter

    $script:ParsecWindowAdapter = @{
        GetForegroundWindowInfo = {
            $window = @($script:IngredientWindows | Where-Object { [int64] $_.handle -eq [int64] $script:IngredientWindowForegroundHandle }) | Select-Object -First 1
            if ($null -eq $window) {
                return $null
            }

            return ConvertTo-ParsecPlainObject -InputObject $window
        }
        GetTopLevelWindows = {
            return @($script:IngredientWindows | ForEach-Object { ConvertTo-ParsecPlainObject -InputObject $_ })
        }
        StepAltTab = {
            $currentIndex = [Array]::IndexOf($script:IngredientAltTabHandles, [int64] $script:IngredientWindowForegroundHandle)
            if ($currentIndex -lt 0 -or $script:IngredientAltTabHandles.Count -eq 0) {
                return [ordered]@{
                    succeeded = $false
                    handle = $script:IngredientWindowForegroundHandle
                }
            }

            $nextIndex = ($currentIndex + 1) % $script:IngredientAltTabHandles.Count
            $nextHandle = [int64] $script:IngredientAltTabHandles[$nextIndex]
            $script:IngredientWindowForegroundHandle = $nextHandle
            $script:IngredientWindowActivationLog += $nextHandle
            return [ordered]@{
                succeeded = $true
                handle = $nextHandle
            }
        }
        ActivateWindow = {
            param($Arguments)

            $handle = [int64] $Arguments.handle
            $script:IngredientWindowActivationLog += $handle
            $window = @($script:IngredientWindows | Where-Object { [int64] $_.handle -eq $handle }) | Select-Object -First 1
            $succeeded = ($null -ne $window) -and -not (@($script:IngredientWindowActivationDeniedHandles) -contains $handle)
            if ($succeeded) {
                $script:IngredientWindowForegroundHandle = $handle
                if ($Arguments.restore_if_minimized -and $window.is_minimized) {
                    $window.is_minimized = $false
                }
            }

            return [ordered]@{
                succeeded = $succeeded
                handle = $handle
                window = if ($null -ne $window) { ConvertTo-ParsecPlainObject -InputObject $window } else { $null }
            }
        }
    }
    $global:ParsecWindowAdapter = $script:ParsecWindowAdapter

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
    $global:ParsecNvidiaAdapter = $script:ParsecNvidiaAdapter

    if (Get-Command -Name 'Set-ParsecModuleVariableValue' -ErrorAction SilentlyContinue) {
        Set-ParsecModuleVariableValue -Name 'ParsecPersonalizationAdapter' -Value $script:ParsecPersonalizationAdapter | Out-Null
        Set-ParsecModuleVariableValue -Name 'ParsecDisplayAdapter' -Value $script:ParsecDisplayAdapter | Out-Null
        Set-ParsecModuleVariableValue -Name 'ParsecWindowAdapter' -Value $script:ParsecWindowAdapter | Out-Null
        Set-ParsecModuleVariableValue -Name 'ParsecNvidiaAdapter' -Value $script:ParsecNvidiaAdapter | Out-Null
    }
}

function Clear-ParsecTestAdapters {
    foreach ($name in @(
            'ParsecPersonalizationAdapter',
            'ParsecDisplayAdapter',
            'ParsecWindowAdapter',
            'ParsecNvidiaAdapter'
        )) {
        Set-Variable -Scope Global -Name $name -Value $null -Force
        if (Get-Command -Name 'Set-ParsecModuleVariableValue' -ErrorAction SilentlyContinue) {
            Set-ParsecModuleVariableValue -Name $name -Value $null | Out-Null
        }
    }
}
