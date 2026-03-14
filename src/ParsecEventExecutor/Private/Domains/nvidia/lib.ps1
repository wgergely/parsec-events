function Initialize-ParsecNvidiaDomain {
    [CmdletBinding()]
    param()

    if (Get-Variable -Name ParsecNvidiaDomain -Scope Script -ErrorAction SilentlyContinue) {
        return
    }

    $script:ParsecNvidiaDomain = @{
        ResolveCustomResolutionContext = {
            param([hashtable] $Arguments, [string] $StateRoot)

            $availability = Invoke-ParsecNvidiaAdapter -Method 'GetAvailability'
            $requestedWidth = [int] $Arguments.width
            $requestedHeight = [int] $Arguments.height
            $observed = Get-ParsecDisplayDomainObservedState
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
        GetResolutionOrientationClass = {
            param([hashtable] $Arguments)

            $width = [int] $Arguments.width
            $height = [int] $Arguments.height
            if ($width -gt $height) { return 'Landscape' }
            if ($height -gt $width) { return 'Portrait' }
            return 'Neutral'
        }
        NormalizeResolutionOrientationClass = {
            param([hashtable] $Arguments)

            switch ([string] $Arguments.orientation) {
                'LandscapeFlipped' { return 'Landscape' }
                'PortraitFlipped' { return 'Portrait' }
                default { return [string] $Arguments.orientation }
            }
        }
        TestResolutionOrientationCompatibility = {
            param([hashtable] $Arguments)

            $context = $Arguments.context
            $requestedOrientation = Invoke-ParsecNvidiaDomain -Method 'GetResolutionOrientationClass' -Arguments @{
                width = [int] $context.width
                height = [int] $context.height
            }
            $rawObservedOrientation = if ($context.target_monitor.Contains('orientation') -and -not [string]::IsNullOrWhiteSpace([string] $context.target_monitor.orientation)) {
                [string] $context.target_monitor.orientation
            }
            else {
                Invoke-ParsecNvidiaDomain -Method 'GetResolutionOrientationClass' -Arguments @{
                    width = [int] $context.target_monitor.bounds.width
                    height = [int] $context.target_monitor.bounds.height
                }
            }
            $observedOrientation = Invoke-ParsecNvidiaDomain -Method 'NormalizeResolutionOrientationClass' -Arguments @{
                orientation = $rawObservedOrientation
            }

            if ($requestedOrientation -eq 'Neutral' -or [string]::IsNullOrWhiteSpace($observedOrientation)) {
                return $null
            }

            if ($requestedOrientation -ne $observedOrientation) {
                return New-ParsecResult -Status 'Failed' -Message ("Requested custom resolution {0}x{1} is '{2}', but monitor '{3}' is currently '{4}'." -f $context.width, $context.height, $requestedOrientation, $context.device_name, $observedOrientation) -Requested @{
                    device_name = $context.device_name
                    width = $context.width
                    height = $context.height
                    refresh_rate_hz = $context.refresh_rate_hz
                    bits_per_pel = $context.bits_per_pel
                } -Observed $context.target_monitor -Outputs @{
                    device_name = $context.device_name
                    requested_orientation = $requestedOrientation
                    observed_orientation = $rawObservedOrientation
                    normalized_observed_orientation = $observedOrientation
                    current_width = $context.target_monitor.bounds.width
                    current_height = $context.target_monitor.bounds.height
                } -Errors @('OrientationMismatch')
            }

            return $null
        }
        GetProbeFailureContext = {
            param([hashtable] $Arguments)

            $probe = $Arguments.probe
            if ($probe -isnot [System.Collections.IDictionary]) {
                return $null
            }

            if ($probe.Contains('availability') -and $null -ne $probe.availability -and -not [bool] $probe.availability.available) {
                return $probe
            }

            if ($probe.Contains('errors') -and @($probe.errors).Count -gt 0) {
                return $probe
            }

            return $null
        }
        GetCustomResolutionMatches = {
            param([hashtable] $Arguments)

            return @(
                @($Arguments.modes) | Where-Object {
                    [int] $_.width -eq [int] $Arguments.width -and
                    [int] $_.height -eq [int] $Arguments.height
                }
            )
        }
        GetCustomResolutionProbe = {
            param([hashtable] $Arguments, [string] $StateRoot)

            $context = Invoke-ParsecNvidiaDomain -Method 'ResolveCustomResolutionContext' -Arguments $Arguments -StateRoot $StateRoot
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
            $matchingCustomModes = @(Invoke-ParsecNvidiaDomain -Method 'GetCustomResolutionMatches' -Arguments @{
                    modes = $customModes
                    width = $context.width
                    height = $context.height
                })
            $matchingSupportedModes = @(Invoke-ParsecNvidiaDomain -Method 'GetCustomResolutionMatches' -Arguments @{
                    modes = $supportedModes
                    width = $context.width
                    height = $context.height
                })

            return [ordered]@{
                context = $context
                custom_modes = $customModes
                supported_modes = $supportedModes
                matching_custom_modes = $matchingCustomModes
                matching_supported_modes = $matchingSupportedModes
            }
        }
        ApplyCustomResolution = {
            param([hashtable] $Arguments, [string] $StateRoot)

            $context = Invoke-ParsecNvidiaDomain -Method 'ResolveCustomResolutionContext' -Arguments $Arguments -StateRoot $StateRoot
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

            $orientationCompatibility = Invoke-ParsecNvidiaDomain -Method 'TestResolutionOrientationCompatibility' -Arguments @{
                context = $context
            }
            if ($null -ne $orientationCompatibility) {
                return $orientationCompatibility
            }

            $existingCustomModes = @(
                Invoke-ParsecNvidiaAdapter -Method 'GetCustomResolutions' -Arguments @{
                    display_id = [uint32] $context.display_target.display_id
                    library_path = [string] $context.display_target.library_path
                }
            )
            $matchingCustomModes = @(Invoke-ParsecNvidiaDomain -Method 'GetCustomResolutionMatches' -Arguments @{
                    modes = $existingCustomModes
                    width = $context.width
                    height = $context.height
                })
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

            $topologyState = Get-ParsecDisplayDomainTopologyCaptureState -ObservedState $context.observed
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
            $topologyRestore = Invoke-ParsecDisplayDomainTopologyReset -TopologyState $topologyState -SnapshotName 'nvidia-custom-resolution-restore'
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
        WaitForCustomResolution = {
            param([hashtable] $Arguments, [string] $StateRoot)

            $probe = Invoke-ParsecNvidiaDomain -Method 'GetCustomResolutionProbe' -Arguments $Arguments -StateRoot $StateRoot
            $failureContext = Invoke-ParsecNvidiaDomain -Method 'GetProbeFailureContext' -Arguments @{ probe = $probe }
            if ($null -ne $failureContext) {
                $context = $failureContext
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
        VerifyCustomResolution = {
            param([hashtable] $Arguments, [string] $StateRoot)

            $probe = Invoke-ParsecNvidiaDomain -Method 'GetCustomResolutionProbe' -Arguments $Arguments -StateRoot $StateRoot
            $failureContext = Invoke-ParsecNvidiaDomain -Method 'GetProbeFailureContext' -Arguments @{ probe = $probe }
            if ($null -ne $failureContext) {
                $context = $failureContext
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

function Invoke-ParsecNvidiaDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Method,

        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    Initialize-ParsecNvidiaDomain
    if (-not $script:ParsecNvidiaDomain.ContainsKey($Method)) {
        throw "NVIDIA domain method '$Method' is not available."
    }

    return & $script:ParsecNvidiaDomain[$Method] $Arguments $StateRoot
}
