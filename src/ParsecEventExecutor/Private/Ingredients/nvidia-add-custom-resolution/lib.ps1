function script:Resolve-ParsecNvidiaCustomResolutionContext {
    param(
        [Parameter(Mandatory)]
        [hashtable] $Arguments,

        [Parameter(Mandatory)]
        [string] $StateRoot
    )

    $availability = Invoke-ParsecNvidiaAdapter -Method 'GetAvailability'
    $requestedWidth = [int] $Arguments.width
    $requestedHeight = [int] $Arguments.height
    $observed = Get-ParsecObservedState
    $targetMonitor = Resolve-ParsecDisplayTargetMonitor -ObservedState $observed -Arguments $Arguments -StateRoot $StateRoot
    if ($null -eq $targetMonitor) {
        return [ordered]@{
            availability = $availability
            observed = $observed
            target_monitor = $null
            width = $requestedWidth
            height = $requestedHeight
            refresh_rate_hz = $null
            bits_per_pel = $null
            errors = @('MonitorNotFound')
            message = 'Target monitor could not be resolved.'
        }
    }

    $deviceName = [string] $targetMonitor.device_name
    $refreshRateHz = if ($Arguments.ContainsKey('refresh_rate_hz') -and $null -ne $Arguments.refresh_rate_hz) {
        [int] $Arguments.refresh_rate_hz
    }
    else {
        60
    }
    $bitsPerPel = if ($Arguments.ContainsKey('bits_per_pel') -and $null -ne $Arguments.bits_per_pel) {
        [int] $Arguments.bits_per_pel
    }
    elseif ($targetMonitor.Contains('display') -and $targetMonitor.display.Contains('bits_per_pel')) {
        [int] $targetMonitor.display.bits_per_pel
    }
    else {
        32
    }

    $displayTarget = $null
    if ($availability.available) {
        try {
            $displayTarget = Invoke-ParsecNvidiaAdapter -Method 'ResolveDisplayTarget' -Arguments @{
                device_name = $deviceName
                library_path = $availability.library_path
            }
        }
        catch {
            return [ordered]@{
                availability = $availability
                observed = $observed
                target_monitor = $targetMonitor
                device_name = $deviceName
                width = $requestedWidth
                height = $requestedHeight
                refresh_rate_hz = $refreshRateHz
                bits_per_pel = $bitsPerPel
                errors = @('DisplayTargetNotResolvable')
                message = $_.Exception.Message
            }
        }
    }

    return [ordered]@{
        availability = $availability
        observed = $observed
        target_monitor = $targetMonitor
        device_name = $deviceName
        display_target = $displayTarget
        width = $requestedWidth
        height = $requestedHeight
        refresh_rate_hz = $refreshRateHz
        bits_per_pel = $bitsPerPel
        errors = @()
        message = $null
    }
}

function script:Get-ParsecResolutionOrientationClass {
    param(
        [Parameter(Mandatory)]
        [int] $Width,

        [Parameter(Mandatory)]
        [int] $Height
    )

    if ($Width -gt $Height) {
        return 'Landscape'
    }

    if ($Height -gt $Width) {
        return 'Portrait'
    }

    return 'Neutral'
}

function script:Test-ParsecNvidiaResolutionOrientationCompatibility {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Context
    )

    $requestedOrientation = Get-ParsecResolutionOrientationClass -Width ([int] $Context.width) -Height ([int] $Context.height)
    $observedOrientation = if ($Context.target_monitor.Contains('orientation') -and -not [string]::IsNullOrWhiteSpace([string] $Context.target_monitor.orientation)) {
        [string] $Context.target_monitor.orientation
    }
    else {
        Get-ParsecResolutionOrientationClass -Width ([int] $Context.target_monitor.bounds.width) -Height ([int] $Context.target_monitor.bounds.height)
    }

    if ($requestedOrientation -eq 'Neutral' -or [string]::IsNullOrWhiteSpace($observedOrientation)) {
        return $null
    }

    if ($requestedOrientation -ne $observedOrientation) {
        return New-ParsecResult -Status 'Failed' -Message ("Requested custom resolution {0}x{1} is '{2}', but monitor '{3}' is currently '{4}'." -f $Context.width, $Context.height, $requestedOrientation, $Context.device_name, $observedOrientation) -Requested @{
            device_name = $Context.device_name
            width = $Context.width
            height = $Context.height
            refresh_rate_hz = $Context.refresh_rate_hz
            bits_per_pel = $Context.bits_per_pel
        } -Observed $Context.target_monitor -Outputs @{
            device_name = $Context.device_name
            requested_orientation = $requestedOrientation
            observed_orientation = $observedOrientation
            current_width = $Context.target_monitor.bounds.width
            current_height = $Context.target_monitor.bounds.height
        } -Errors @('OrientationMismatch')
    }

    return $null
}

function script:Get-ParsecNvidiaCustomResolutionMatches {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Modes,

        [Parameter(Mandatory)]
        [int] $Width,

        [Parameter(Mandatory)]
        [int] $Height
    )

    return @(
        $Modes | Where-Object {
            [int] $_.width -eq $Width -and
            [int] $_.height -eq $Height
        }
    )
}

function script:Get-ParsecNvidiaCustomResolutionProbe {
    param(
        [Parameter(Mandatory)]
        [hashtable] $Arguments,

        [Parameter(Mandatory)]
        [string] $StateRoot
    )

    $context = Resolve-ParsecNvidiaCustomResolutionContext -Arguments $Arguments -StateRoot $StateRoot
    if (-not $context.availability.available -or @($context.errors).Count -gt 0) {
        return $context
    }

    $customModes = @(
        Invoke-ParsecNvidiaAdapter -Method 'GetCustomResolutions' -Arguments @{
            display_id = [uint32] $context.display_target.display_id
            library_path = [string] $context.display_target.library_path
        }
    )
    $supportedModes = @(Get-ParsecSupportedDisplayModes -DeviceName $context.device_name)
    $matchingCustomModes = @(Get-ParsecNvidiaCustomResolutionMatches -Modes $customModes -Width $context.width -Height $context.height)
    $matchingSupportedModes = @(Get-ParsecNvidiaCustomResolutionMatches -Modes $supportedModes -Width $context.width -Height $context.height)

    return [ordered]@{
        context = $context
        custom_modes = $customModes
        supported_modes = $supportedModes
        matching_custom_modes = $matchingCustomModes
        matching_supported_modes = $matchingSupportedModes
    }
}

function Get-ParsecIngredientOperations {
    return @{
        apply = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)

            $context = Resolve-ParsecNvidiaCustomResolutionContext -Arguments $Arguments -StateRoot $StateRoot
            if (-not $context.availability.available) {
                return New-ParsecResult -Status 'Failed' -Message $context.availability.message -Requested $Arguments -Observed $context.observed -Outputs @{
                    requested_width = $context.width
                    requested_height = $context.height
                    refresh_rate_hz = $context.refresh_rate_hz
                    bits_per_pel = $context.bits_per_pel
                    library_path = $context.availability.library_path
                } -Errors @('CapabilityUnavailable')
            }

            if (@($context.errors).Count -gt 0) {
                return New-ParsecResult -Status 'Failed' -Message $context.message -Requested $Arguments -Observed $context.observed -Outputs @{
                    requested_width = $context.width
                    requested_height = $context.height
                    refresh_rate_hz = $context.refresh_rate_hz
                    bits_per_pel = $context.bits_per_pel
                    library_path = $context.availability.library_path
                } -Errors @($context.errors)
            }

            $orientationCompatibility = Test-ParsecNvidiaResolutionOrientationCompatibility -Context $context
            if ($null -ne $orientationCompatibility) {
                return $orientationCompatibility
            }

            $existingCustomModes = @(
                Invoke-ParsecNvidiaAdapter -Method 'GetCustomResolutions' -Arguments @{
                    display_id = [uint32] $context.display_target.display_id
                    library_path = [string] $context.display_target.library_path
                }
            )
            $matchingCustomModes = @(Get-ParsecNvidiaCustomResolutionMatches -Modes $existingCustomModes -Width $context.width -Height $context.height)
            if ($matchingCustomModes.Count -gt 0) {
                return New-ParsecResult -Status 'Succeeded' -Message ("NVIDIA custom resolution {0}x{1} already exists for '{2}'." -f $context.width, $context.height, $context.device_name) -Requested $Arguments -Observed $context.target_monitor -Outputs @{
                    device_name = $context.device_name
                    normalized_display_name = $context.display_target.normalized_display_name
                    display_id = [uint32] $context.display_target.display_id
                    width = $context.width
                    height = $context.height
                    refresh_rate_hz = $context.refresh_rate_hz
                    bits_per_pel = $context.bits_per_pel
                    already_present = $true
                    custom_mode_count = @($existingCustomModes).Count
                    custom_modes_sample = @($existingCustomModes | Select-Object -First 10)
                    library_path = $context.display_target.library_path
                }
            }

            $topologyState = Get-ParsecDisplayTopologyCaptureState -ObservedState $context.observed
            $result = Invoke-ParsecNvidiaAdapter -Method 'AddCustomResolution' -Arguments @{
                device_name = $context.device_name
                normalized_display_name = $context.display_target.normalized_display_name
                display_id = [uint32] $context.display_target.display_id
                width = $context.width
                height = $context.height
                refresh_rate_hz = $context.refresh_rate_hz
                bits_per_pel = $context.bits_per_pel
                library_path = $context.display_target.library_path
            }
            $topologyRestore = Invoke-ParsecDisplayTopologyReset -TopologyState $topologyState -SnapshotName 'nvidia-custom-resolution-restore'
            $result.Requested = [ordered]@{
                device_name = $context.device_name
                normalized_display_name = $context.display_target.normalized_display_name
                display_id = [uint32] $context.display_target.display_id
                width = $context.width
                height = $context.height
                refresh_rate_hz = $context.refresh_rate_hz
                bits_per_pel = $context.bits_per_pel
            }
            $result.Observed = ConvertTo-ParsecPlainObject -InputObject $context.target_monitor
            $outputs = [ordered]@{
                device_name = $context.device_name
                normalized_display_name = $context.display_target.normalized_display_name
                display_id = [uint32] $context.display_target.display_id
                width = $context.width
                height = $context.height
                refresh_rate_hz = $context.refresh_rate_hz
                bits_per_pel = $context.bits_per_pel
                already_present = $false
                library_path = $context.display_target.library_path
                topology_restore = ConvertTo-ParsecPlainObject -InputObject $topologyRestore
            }
            foreach ($key in @($result.Outputs.Keys)) {
                $outputs[$key] = $result.Outputs[$key]
            }

            $result.Outputs = $outputs
            if (-not (Test-ParsecSuccessfulStatus -Status $topologyRestore.Status)) {
                $result.Status = 'Failed'
                $result.Message = "Custom resolution attempt completed but topology restore failed: $($topologyRestore.Message)"
                $result.Errors = @($result.Errors + 'TopologyRestoreFailed')
            }
            return $result
        }
        wait = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)

            $probe = Get-ParsecNvidiaCustomResolutionProbe -Arguments $Arguments -StateRoot $StateRoot
            if ($probe -is [System.Collections.IDictionary] -and $probe.Contains('errors') -and @($probe.errors).Count -gt 0) {
                $context = $probe
                $errorCode = if (-not $context.availability.available) { 'CapabilityUnavailable' } else { $context.errors[0] }
                return New-ParsecResult -Status 'Failed' -Message $(if ($null -ne $context.message) { $context.message } else { $context.availability.message }) -Requested $Arguments -Observed $context.observed -Outputs @{
                    requested_width = $context.width
                    requested_height = $context.height
                    refresh_rate_hz = $context.refresh_rate_hz
                    bits_per_pel = $context.bits_per_pel
                    library_path = $context.availability.library_path
                } -Errors @($errorCode)
            }

            $context = $probe.context
            if (@($probe.matching_supported_modes).Count -eq 0) {
                return New-ParsecResult -Status 'Failed' -Message ("NVIDIA custom resolution {0}x{1} is not yet visible in supported modes for '{2}'." -f $context.width, $context.height, $context.device_name) -Requested $Arguments -Observed $context.target_monitor -Outputs @{
                    device_name = $context.device_name
                    display_id = [uint32] $context.display_target.display_id
                    width = $context.width
                    height = $context.height
                    refresh_rate_hz = $context.refresh_rate_hz
                    bits_per_pel = $context.bits_per_pel
                    custom_mode_present = (@($probe.matching_custom_modes).Count -gt 0)
                    supported_mode_present = $false
                    custom_mode_count = @($probe.custom_modes).Count
                    supported_mode_count = @($probe.supported_modes).Count
                    custom_modes_sample = @($probe.custom_modes | Select-Object -First 10)
                    supported_modes_sample = @($probe.supported_modes | Select-Object -First 10)
                } -Errors @('ReadinessPending')
            }

            return New-ParsecResult -Status 'Succeeded' -Message ("NVIDIA custom resolution {0}x{1} is ready on '{2}'." -f $context.width, $context.height, $context.device_name) -Requested $Arguments -Observed $context.target_monitor -Outputs @{
                device_name = $context.device_name
                display_id = [uint32] $context.display_target.display_id
                width = $context.width
                height = $context.height
                refresh_rate_hz = $context.refresh_rate_hz
                bits_per_pel = $context.bits_per_pel
                custom_mode_present = (@($probe.matching_custom_modes).Count -gt 0)
                supported_mode_present = $true
                custom_mode_count = @($probe.custom_modes).Count
                supported_mode_count = @($probe.supported_modes).Count
            }
        }
        verify = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)

            $probe = Get-ParsecNvidiaCustomResolutionProbe -Arguments $Arguments -StateRoot $StateRoot
            if ($probe -is [System.Collections.IDictionary] -and $probe.Contains('errors') -and @($probe.errors).Count -gt 0) {
                $context = $probe
                $errorCode = if (-not $context.availability.available) { 'CapabilityUnavailable' } else { $context.errors[0] }
                return New-ParsecResult -Status 'Failed' -Message $(if ($null -ne $context.message) { $context.message } else { $context.availability.message }) -Requested $Arguments -Observed $context.observed -Outputs @{
                    requested_width = $context.width
                    requested_height = $context.height
                    refresh_rate_hz = $context.refresh_rate_hz
                    bits_per_pel = $context.bits_per_pel
                    library_path = $context.availability.library_path
                } -Errors @($errorCode)
            }

            $context = $probe.context
            if (@($probe.matching_supported_modes).Count -eq 0) {
                return New-ParsecResult -Status 'Failed' -Message ("NVIDIA custom resolution {0}x{1} is not available in supported modes for '{2}'." -f $context.width, $context.height, $context.device_name) -Requested $Arguments -Observed $context.target_monitor -Outputs @{
                    device_name = $context.device_name
                    normalized_display_name = $context.display_target.normalized_display_name
                    display_id = [uint32] $context.display_target.display_id
                    width = $context.width
                    height = $context.height
                    refresh_rate_hz = $context.refresh_rate_hz
                    bits_per_pel = $context.bits_per_pel
                    custom_mode_present = (@($probe.matching_custom_modes).Count -gt 0)
                    supported_mode_present = $false
                    custom_mode_count = @($probe.custom_modes).Count
                    supported_mode_count = @($probe.supported_modes).Count
                    custom_modes_sample = @($probe.custom_modes | Select-Object -First 10)
                    supported_modes_sample = @($probe.supported_modes | Select-Object -First 10)
                } -Errors @('CustomResolutionUnavailable')
            }

            return New-ParsecResult -Status 'Succeeded' -Message ("NVIDIA custom resolution {0}x{1} is available for '{2}'." -f $context.width, $context.height, $context.device_name) -Requested $Arguments -Observed $context.target_monitor -Outputs @{
                device_name = $context.device_name
                normalized_display_name = $context.display_target.normalized_display_name
                display_id = [uint32] $context.display_target.display_id
                width = $context.width
                height = $context.height
                refresh_rate_hz = $context.refresh_rate_hz
                bits_per_pel = $context.bits_per_pel
                custom_mode_present = (@($probe.matching_custom_modes).Count -gt 0)
                supported_mode_present = $true
                custom_mode_count = @($probe.custom_modes).Count
                supported_mode_count = @($probe.supported_modes).Count
            }
        }
    }
}
