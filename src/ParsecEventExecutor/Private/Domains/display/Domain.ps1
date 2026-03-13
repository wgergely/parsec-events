function Invoke-ParsecDisplayDomainCaptureTarget {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $observed = Get-ParsecObservedState
    $targetMonitor = Resolve-ParsecDisplayTargetMonitor -ObservedState $observed -Arguments $Arguments -StateRoot $StateRoot
    return [ordered]@{
        observed = $observed
        target_monitor = $targetMonitor
    }
}

function Invoke-ParsecDisplayDomainCaptureMonitorState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Domain,

        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $capture = Invoke-ParsecDisplayDomainCaptureTarget -Arguments $Arguments -StateRoot $StateRoot
    if ($null -eq $capture.target_monitor) {
        return New-ParsecResult -Status 'Failed' -Message 'Target monitor could not be resolved.' -Observed $capture.observed -Errors @('MonitorNotFound')
    }

    return Get-ParsecDisplayCaptureResult -ObservedState $capture.observed -DeviceName ([string] $capture.target_monitor.device_name) -Domain $Domain
}

function Invoke-ParsecDisplayDomainApplyResolution {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $supportedModes = @(Get-ParsecSupportedDisplayModes -DeviceName $deviceName)
    $supportedModeCount = @($supportedModes).Count
    $requestedWidth = [int] $Arguments.width
    $requestedHeight = [int] $Arguments.height
    $matchingMode = @(
        $supportedModes | Where-Object {
            [int] $_.width -eq $requestedWidth -and
            [int] $_.height -eq $requestedHeight
        } | Select-Object -First 1
    )

    if ($matchingMode.Count -eq 0) {
        return New-ParsecResult -Status 'Failed' -Message "Resolution ${requestedWidth}x${requestedHeight} is not available on '$deviceName'." -Requested $Arguments -Outputs @{
            device_name = $deviceName
            width = $requestedWidth
            height = $requestedHeight
            supported_mode_count = $supportedModeCount
            supported_modes_sample = @($supportedModes | Select-Object -First 10)
        } -Errors @('UnsupportedResolution')
    }

    $result = Invoke-ParsecDisplayAdapter -Method 'SetResolution' -Arguments @{
        device_name = $deviceName
        width = $requestedWidth
        height = $requestedHeight
    }
    $result.Requested = [ordered]@{
        device_name = $deviceName
        width = $requestedWidth
        height = $requestedHeight
    }
    $result.Outputs = [ordered]@{
        device_name = $deviceName
        width = $requestedWidth
        height = $requestedHeight
        supported_mode_count = $supportedModeCount
        supported_modes_sample = @($supportedModes | Select-Object -First 10)
    }
    return $result
}

function Invoke-ParsecDisplayDomainWaitResolution {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $observed = Get-ParsecObservedState
    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $deviceName
    if ($null -eq $monitor) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' not found during readiness probe." -Observed $observed -Errors @('MonitorNotFound')
    }

    $requestedWidth = [int] $Arguments.width
    $requestedHeight = [int] $Arguments.height
    $observedWidth = if ($monitor.Contains('bounds')) { [int] $monitor.bounds.width } else { $null }
    $observedHeight = if ($monitor.Contains('bounds')) { [int] $monitor.bounds.height } else { $null }
    if ($observedWidth -ne $requestedWidth -or $observedHeight -ne $requestedHeight) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' resolution is still settling." -Observed $monitor -Outputs @{
            device_name = $deviceName
            width = $requestedWidth
            height = $requestedHeight
            observed_width = $observedWidth
            observed_height = $observedHeight
        } -Errors @('ReadinessPending')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Monitor resolution is ready.' -Observed $monitor -Outputs @{
        device_name = $deviceName
        width = $requestedWidth
        height = $requestedHeight
    }
}

function Invoke-ParsecDisplayDomainVerifyResolution {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $observed = Get-ParsecObservedState
    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $deviceName
    if ($null -eq $monitor) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' not found." -Observed $observed -Errors @('MonitorNotFound')
    }

    if ($monitor.bounds.width -ne [int] $Arguments.width -or $monitor.bounds.height -ne [int] $Arguments.height) {
        $supportedModes = @(Get-ParsecSupportedDisplayModes -DeviceName $deviceName)
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' resolution mismatch." -Observed $monitor -Outputs @{
            device_name = $deviceName
            width = [int] $Arguments.width
            height = [int] $Arguments.height
            supported_mode_count = @($supportedModes).Count
            supported_modes_sample = @($supportedModes | Select-Object -First 10)
        } -Errors @('ResolutionDrift')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Monitor resolution matches.' -Observed $monitor -Outputs @{
        device_name = $deviceName
        width = [int] $Arguments.width
        height = [int] $Arguments.height
    }
}

function Invoke-ParsecDisplayDomainResetResolution {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedMonitor = Get-ParsecDisplayResetMonitorState -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -eq $capturedMonitor -or -not $capturedMonitor.Contains('bounds')) {
        return New-ParsecResult -Status 'Failed' -Message 'Captured resolution state does not include a resettable value.' -Errors @('MissingCapturedState')
    }

    return Invoke-ParsecDisplayAdapter -Method 'SetResolution' -Arguments @{
        device_name = [string] $capturedMonitor.device_name
        width = [int] $capturedMonitor.bounds.width
        height = [int] $capturedMonitor.bounds.height
    }
}

function Invoke-ParsecDisplayDomainApplyEnsureResolution {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{}
    )

    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $supportedModes = @(Get-ParsecSupportedDisplayModes -DeviceName $deviceName)
    $requestedWidth = [int] $Arguments.width
    $requestedHeight = [int] $Arguments.height
    $requestedOrientation = if ($Arguments.Contains('orientation')) { [string] $Arguments.orientation } else { $null }
    $matchingMode = @($supportedModes | Where-Object {
            $_.width -eq $requestedWidth -and
            $_.height -eq $requestedHeight -and
            ($null -eq $requestedOrientation -or $_.orientation -eq $requestedOrientation)
        } | Select-Object -First 1)

    $resolutionResult = Invoke-ParsecDisplayDomainApplyResolution -Arguments @{
        device_name = $deviceName
        width = $requestedWidth
        height = $requestedHeight
    } -StateRoot $StateRoot
    if (-not (Test-ParsecSuccessfulStatus -Status $resolutionResult.Status)) {
        return $resolutionResult
    }

    if ($requestedOrientation) {
        $orientationResult = Invoke-ParsecDisplayDomainApplyOrientation -Arguments @{
            device_name = $deviceName
            orientation = $requestedOrientation
        } -StateRoot $StateRoot
        if (-not (Test-ParsecSuccessfulStatus -Status $orientationResult.Status)) {
            return $orientationResult
        }
    }

    return New-ParsecResult -Status 'Succeeded' -Message "Ensured resolution ${requestedWidth}x${requestedHeight} on '$deviceName'." -Requested $Arguments -Outputs @{
        device_name = $deviceName
        width = $requestedWidth
        height = $requestedHeight
        orientation = $requestedOrientation
        mode_preexisting = ($matchingMode.Count -gt 0)
        supported_mode_count = @($supportedModes).Count
        supported_modes_sample = @($supportedModes | Select-Object -First 10)
    }
}

function Invoke-ParsecDisplayDomainVerifyEnsureResolution {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $observed = Get-ParsecObservedState
    $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $deviceName
    if ($null -eq $monitor) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' not found." -Observed $observed
    }

    if ($monitor.bounds.width -ne [int] $Arguments.width -or $monitor.bounds.height -ne [int] $Arguments.height) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' resolution mismatch." -Observed $monitor
    }

    if ($Arguments.Contains('orientation') -and $monitor.orientation -ne [string] $Arguments.orientation) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' orientation mismatch." -Observed $monitor
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Ensured resolution matches.' -Observed $monitor
}

function Invoke-ParsecDisplayDomainResetEnsureResolution {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedMonitor = Get-ParsecDisplayResetMonitorState -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -eq $capturedMonitor -or -not $capturedMonitor.Contains('bounds')) {
        return New-ParsecResult -Status 'Failed' -Message 'Captured ensured-resolution state does not include a resettable value.' -Errors @('MissingCapturedState')
    }

    return Invoke-ParsecDisplayDomainResetResolution -Arguments @{ captured_state = $capturedMonitor } -ExecutionResult $ExecutionResult
}

function Invoke-ParsecDisplayDomainApplyOrientation {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $result = Invoke-ParsecDisplayAdapter -Method 'SetOrientation' -Arguments @{
        device_name = $deviceName
        orientation = [string] $Arguments.orientation
    }
    $result.Requested = [ordered]@{
        device_name = $deviceName
        orientation = [string] $Arguments.orientation
    }
    $result.Outputs = [ordered]@{
        device_name = $deviceName
        orientation = [string] $Arguments.orientation
    }
    return $result
}

function Invoke-ParsecDisplayDomainWaitOrientation {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $observed = Get-ParsecObservedState
    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $deviceName
    if ($null -eq $monitor) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' not found during readiness probe." -Observed $observed -Errors @('MonitorNotFound')
    }

    $expectedOrientation = [string] $Arguments.orientation
    if ([string] $monitor.orientation -ne $expectedOrientation) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' orientation is still settling." -Observed $monitor -Outputs @{
            device_name = $deviceName
            orientation = $expectedOrientation
            observed_orientation = [string] $monitor.orientation
        } -Errors @('ReadinessPending')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Monitor orientation is ready.' -Observed $monitor -Outputs @{
        device_name = $deviceName
        orientation = $expectedOrientation
    }
}

function Invoke-ParsecDisplayDomainVerifyOrientation {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $observed = Get-ParsecObservedState
    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $deviceName
    if ($null -eq $monitor) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' not found." -Observed $observed -Errors @('MonitorNotFound')
    }

    if ([string] $monitor.orientation -ne [string] $Arguments.orientation) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' orientation mismatch." -Observed $monitor -Outputs @{
            device_name = $deviceName
            orientation = [string] $Arguments.orientation
        } -Errors @('OrientationDrift')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Monitor orientation matches.' -Observed $monitor -Outputs @{
        device_name = $deviceName
        orientation = [string] $Arguments.orientation
    }
}

function Invoke-ParsecDisplayDomainResetOrientation {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedMonitor = Get-ParsecDisplayResetMonitorState -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -eq $capturedMonitor -or -not $capturedMonitor.Contains('orientation') -or $capturedMonitor.orientation -eq 'Unknown') {
        return New-ParsecResult -Status 'Failed' -Message 'Captured orientation state does not include a resettable value.' -Errors @('MissingCapturedState')
    }

    return Invoke-ParsecDisplayAdapter -Method 'SetOrientation' -Arguments @{
        device_name = [string] $capturedMonitor.device_name
        orientation = [string] $capturedMonitor.orientation
    }
}

function Invoke-ParsecDisplayDomainCapturePrimary {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    $observed = Get-ParsecObservedState
    $primary = @($observed.monitors) | Where-Object { $_.is_primary } | Select-Object -First 1
    $outputs = [ordered]@{ captured_state = [ordered]@{ primary_monitor = $primary } }
    if ($Arguments.Contains('device_name')) {
        $outputs.captured_state.requested_monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $Arguments.device_name
    }
    return New-ParsecResult -Status 'Succeeded' -Message 'Captured primary monitor state.' -Observed $outputs.captured_state -Outputs $outputs
}

function Invoke-ParsecDisplayDomainApplyPrimary {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    return Invoke-ParsecDisplayAdapter -Method 'SetPrimary' -Arguments $Arguments
}

function Invoke-ParsecDisplayDomainVerifyPrimary {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    $observed = Get-ParsecObservedState
    $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $Arguments.device_name
    if ($null -eq $monitor) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' not found."
    }
    if (-not [bool] $monitor.is_primary) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' is not primary." -Observed $monitor
    }
    return New-ParsecResult -Status 'Succeeded' -Message 'Monitor is primary.' -Observed $monitor
}

function Invoke-ParsecDisplayDomainResetPrimary {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedMonitor = Get-ParsecDisplayResetMonitorState -Arguments $Arguments -ExecutionResult $ExecutionResult -Preference 'primary'
    if ($null -eq $capturedMonitor) {
        return New-ParsecResult -Status 'Failed' -Message 'Captured primary-monitor state does not include a resettable value.' -Errors @('MissingCapturedState')
    }

    return Invoke-ParsecDisplayAdapter -Method 'SetPrimary' -Arguments @{
        device_name = [string] $capturedMonitor.device_name
    }
}

function Invoke-ParsecDisplayDomainCaptureEnabled {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    $observed = Get-ParsecObservedState
    return Get-ParsecDisplayCaptureResult -ObservedState $observed -DeviceName $Arguments.device_name -Domain 'display enabled-state'
}

function Invoke-ParsecDisplayDomainApplyEnabled {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    return Invoke-ParsecDisplayAdapter -Method 'SetEnabled' -Arguments $Arguments
}

function Invoke-ParsecDisplayDomainVerifyEnabled {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    $observed = Get-ParsecObservedState
    $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $Arguments.device_name
    if ($null -eq $monitor) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' not found."
    }
    if ([bool] $monitor.enabled -ne [bool] $Arguments.enabled) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' enabled state mismatch." -Observed $monitor
    }
    return New-ParsecResult -Status 'Succeeded' -Message 'Monitor enabled state matches.' -Observed $monitor
}

function Invoke-ParsecDisplayDomainResetEnabled {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedMonitor = Get-ParsecDisplayResetMonitorState -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -eq $capturedMonitor -or -not $capturedMonitor.Contains('enabled')) {
        return New-ParsecResult -Status 'Failed' -Message 'Captured enabled-state does not include a resettable value.' -Errors @('MissingCapturedState')
    }

    return Invoke-ParsecDisplayAdapter -Method 'SetEnabled' -Arguments @{
        device_name = [string] $capturedMonitor.device_name
        enabled = [bool] $capturedMonitor.enabled
        bounds = if ($capturedMonitor.Contains('bounds')) { $capturedMonitor.bounds } else { $null }
    }
}

function Invoke-ParsecDisplayDomainCaptureActiveDisplays {
    [CmdletBinding()]
    param()

    $observed = Get-ParsecObservedState
    $capturedState = Get-ParsecDisplayTopologyCaptureState -ObservedState $observed
    return New-ParsecResult -Status 'Succeeded' -Message 'Captured active display topology.' -Observed $observed -Outputs @{
        captured_state = $capturedState
    }
}

function Invoke-ParsecDisplayDomainApplyActiveDisplays {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $observed = Get-ParsecObservedState
    $resolution = Resolve-ParsecActiveDisplayTargetState -ObservedState $observed -Arguments $Arguments -StateRoot $StateRoot
    if (-not (Test-ParsecSuccessfulStatus -Status $resolution.Status)) {
        return $resolution
    }

    $targetState = ConvertTo-ParsecPlainObject -InputObject $resolution.Outputs.target_state
    $result = Invoke-ParsecDisplayTopologyReset -TopologyState $targetState -SnapshotName 'set-activedisplays'
    $result.Requested = [ordered]@{
        screen_ids = @($resolution.Outputs.requested_screen_ids)
    }
    $result.Outputs = [ordered]@{
        target_state = $targetState
        requested_screen_ids = @($resolution.Outputs.requested_screen_ids)
        requested_device_names = @($resolution.Outputs.requested_device_names)
        primary_device_name = [string] $resolution.Outputs.primary_device_name
        topology_restore = if ($result.Outputs.Contains('actions')) {
            [ordered]@{
                snapshot_name = [string] $result.Outputs.snapshot_name
                actions = @($result.Outputs.actions)
            }
        } else { $null }
    }
    if (Test-ParsecSuccessfulStatus -Status $result.Status) {
        $result.Message = 'Applied active display topology.'
    }

    return $result
}

function Invoke-ParsecDisplayDomainWaitActiveDisplays {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $targetState = Resolve-ParsecActiveDisplayTargetStateForOperation -ExecutionResult $ExecutionResult -Arguments $Arguments -StateRoot $StateRoot
    if ($targetState -isnot [System.Collections.IDictionary]) {
        return $targetState
    }

    $observed = Get-ParsecObservedState
    $comparison = Compare-ParsecActiveDisplaySelectionState -TargetState $targetState -ObservedState $observed
    if (-not (Test-ParsecSuccessfulStatus -Status $comparison.Status)) {
        return New-ParsecResult -Status 'Failed' -Message 'Display topology is still settling.' -Observed $observed -Outputs @{
            mismatches = if ($comparison.Outputs.Contains('mismatches')) { @($comparison.Outputs.mismatches) } else { @() }
            target_state = $targetState
        } -Errors @('ReadinessPending')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Display topology is ready.' -Observed $observed -Outputs @{
        target_state = $targetState
    }
}

function Invoke-ParsecDisplayDomainVerifyActiveDisplays {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $targetState = Resolve-ParsecActiveDisplayTargetStateForOperation -ExecutionResult $ExecutionResult -Arguments $Arguments -StateRoot $StateRoot
    if ($targetState -isnot [System.Collections.IDictionary]) {
        return $targetState
    }

    $observed = Get-ParsecObservedState
    $comparison = Compare-ParsecActiveDisplaySelectionState -TargetState $targetState -ObservedState $observed
    if (-not (Test-ParsecSuccessfulStatus -Status $comparison.Status)) {
        return New-ParsecResult -Status 'Failed' -Message 'Observed display topology does not match the requested active-display set.' -Observed $observed -Outputs @{
            mismatches = if ($comparison.Outputs.Contains('mismatches')) { @($comparison.Outputs.mismatches) } else { @() }
            target_state = $targetState
        } -Errors @('ActiveDisplayDrift')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Observed display topology matches the requested active-display set.' -Observed $observed -Outputs @{
        target_state = $targetState
    }
}

function Invoke-ParsecDisplayDomainResetActiveDisplays {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -eq $capturedState) {
        return New-ParsecResult -Status 'Failed' -Message 'Captured topology state does not include a resettable value.' -Errors @('MissingCapturedState')
    }

    return Invoke-ParsecDisplayTopologyReset -TopologyState $capturedState -SnapshotName 'set-activedisplays-reset'
}

function Invoke-ParsecDisplayDomainCaptureScaling {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    $observed = Get-ParsecObservedState
    if ($Arguments.Contains('device_name')) {
        $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $Arguments.device_name
        if ($null -eq $monitor) {
            return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' not found." -Observed $observed -Errors @('MonitorNotFound')
        }
        $scalePercent = if ($monitor.Contains('display') -and $monitor.display.Contains('scale_percent')) { $monitor.display.scale_percent } else { $null }
        $effectiveDpiX = if ($monitor.Contains('display') -and $monitor.display.Contains('effective_dpi_x')) { $monitor.display.effective_dpi_x } else { $null }
        $effectiveDpiY = if ($monitor.Contains('display') -and $monitor.display.Contains('effective_dpi_y')) { $monitor.display.effective_dpi_y } else { $null }
        $textScalePercent = if ($observed.Contains('font_scaling') -and $observed.font_scaling.Contains('text_scale_percent')) { $observed.font_scaling.text_scale_percent } else { $null }
        return New-ParsecResult -Status 'Succeeded' -Message "Captured display scaling state for '$($Arguments.device_name)'." -Observed @{ device_name = $monitor.device_name; scale_percent = $scalePercent; effective_dpi_x = $effectiveDpiX; effective_dpi_y = $effectiveDpiY; text_scale_percent = $textScalePercent } -Outputs @{ captured_state = @{ device_name = $monitor.device_name; scale_percent = $scalePercent; effective_dpi_x = $effectiveDpiX; effective_dpi_y = $effectiveDpiY; text_scale_percent = $textScalePercent } }
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Captured display scaling state.' -Observed @{ scaling = $observed.scaling; font_scaling = $observed.font_scaling } -Outputs @{ captured_state = @{ scaling = $observed.scaling; font_scaling = $observed.font_scaling; ui_scale_percent = $observed.scaling.ui_scale_percent; text_scale_percent = $observed.font_scaling.text_scale_percent } }
}

function Invoke-ParsecDisplayDomainApplyScaling {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    return Invoke-ParsecDisplayAdapter -Method 'SetScaling' -Arguments $Arguments
}

function Invoke-ParsecDisplayDomainVerifyScaling {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    $observed = Get-ParsecObservedState
    $currentValue = $null
    $expectedValue = if ($Arguments.Contains('text_scale_percent')) { [int] $Arguments.text_scale_percent } elseif ($Arguments.Contains('ui_scale_percent')) { [int] $Arguments.ui_scale_percent } elseif ($Arguments.Contains('scale_percent')) { [int] $Arguments.scale_percent } elseif ($Arguments.Contains('value')) { [int] $Arguments.value } else { $null }
    if ($Arguments.Contains('device_name')) {
        $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $Arguments.device_name
        if ($null -ne $monitor -and $monitor.Contains('display') -and $monitor.display.Contains('scale_percent')) { $currentValue = $monitor.display.scale_percent }
    } elseif ($Arguments.Contains('text_scale_percent') -and $observed.Contains('font_scaling') -and $observed.font_scaling.Contains('text_scale_percent')) { $currentValue = $observed.font_scaling.text_scale_percent } elseif (($Arguments.Contains('ui_scale_percent') -or $Arguments.Contains('scale_percent') -or $Arguments.Contains('value')) -and $observed.scaling.Contains('ui_scale_percent')) { $currentValue = $observed.scaling.ui_scale_percent } elseif ($observed.scaling.Contains('text_scale_percent')) { $currentValue = $observed.scaling.text_scale_percent }
    if ($null -eq $currentValue -or $null -eq $expectedValue -or $currentValue -ne $expectedValue) {
        return New-ParsecResult -Status 'Failed' -Message 'Display scaling mismatch.' -Observed $observed.scaling
    }
    return New-ParsecResult -Status 'Succeeded' -Message 'Display scaling matches.' -Observed $observed.scaling
}

function Invoke-ParsecDisplayDomainResetScaling {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedState = if ($Arguments.Contains('captured_state') -and $Arguments.captured_state -is [System.Collections.IDictionary]) { ConvertTo-ParsecPlainObject -InputObject $Arguments.captured_state } elseif ($null -ne $ExecutionResult -and $ExecutionResult.Outputs.captured_state) { ConvertTo-ParsecPlainObject -InputObject $ExecutionResult.Outputs.captured_state } else { $null }
    if ($null -ne $capturedState -and $capturedState.Contains('text_scale_percent')) {
        return Invoke-ParsecDisplayAdapter -Method 'SetScaling' -Arguments @{ text_scale_percent = [int] $capturedState.text_scale_percent }
    }
    if ($null -ne $capturedState -and $capturedState.Contains('ui_scale_percent')) {
        return Invoke-ParsecDisplayAdapter -Method 'SetScaling' -Arguments @{ ui_scale_percent = [int] $capturedState.ui_scale_percent }
    }
    return New-ParsecResult -Status 'Failed' -Message 'Captured scaling state does not include a resettable text scaling value.' -Errors @('CapabilityUnavailable')
}

function Resolve-ParsecDisplayDomainUiScaleExpectedValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    if ($null -ne $ExecutionResult -and $ExecutionResult.Outputs -and $ExecutionResult.Outputs.Contains('ui_scale_percent')) { return [int] $ExecutionResult.Outputs.ui_scale_percent }
    if ($Arguments.Contains('ui_scale_percent')) { return [int] $Arguments.ui_scale_percent }
    if ($Arguments.Contains('scale_percent')) { return [int] $Arguments.scale_percent }
    if ($Arguments.Contains('value')) { return [int] $Arguments.value }
    $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -ne $capturedState -and $capturedState.Contains('ui_scale_percent')) { return [int] $capturedState.ui_scale_percent }
    throw 'UI scale operation requires ui_scale_percent, scale_percent, or value.'
}

function Invoke-ParsecDisplayDomainCaptureTextScale {
    [CmdletBinding()]
    param()

    $observed = Get-ParsecObservedState
    $textScalePercent = if ($observed.Contains('font_scaling') -and $observed.font_scaling.Contains('text_scale_percent')) { [int] $observed.font_scaling.text_scale_percent } else { $null }
    return New-ParsecResult -Status 'Succeeded' -Message 'Captured text scaling state.' -Observed @{ text_scale_percent = $textScalePercent } -Outputs @{ captured_state = @{ text_scale_percent = $textScalePercent } }
}

function Invoke-ParsecDisplayDomainCaptureUiScale {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $observed = Get-ParsecObservedState
    $targetMonitor = Resolve-ParsecDisplayTargetMonitor -ObservedState $observed -Arguments $Arguments -StateRoot $StateRoot
    if ($null -eq $targetMonitor) {
        return New-ParsecResult -Status 'Failed' -Message 'Target monitor could not be resolved.' -Observed $observed -Errors @('MonitorNotFound')
    }
    $uiScalePercent = if ($targetMonitor.display -is [System.Collections.IDictionary] -and $targetMonitor.display.Contains('scale_percent')) { [int] $targetMonitor.display.scale_percent } else { $null }
    return New-ParsecResult -Status 'Succeeded' -Message 'Captured UI scaling state.' -Observed @{ device_name = [string] $targetMonitor.device_name; ui_scale_percent = $uiScalePercent } -Outputs @{ captured_state = @{ device_name = [string] $targetMonitor.device_name; ui_scale_percent = $uiScalePercent } }
}

function Invoke-ParsecDisplayDomainApplyTextScale { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()] $ExecutionResult) $v = if ($Arguments.Contains('text_scale_percent')) { [int] $Arguments.text_scale_percent } elseif ($Arguments.Contains('value')) { [int] $Arguments.value } else { [int] (Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult).text_scale_percent }; $r = Invoke-ParsecPersonalizationAdapter -Method 'SetTextScale' -Arguments @{ text_scale_percent = $v }; $r.Requested = [ordered]@{ text_scale_percent = $v }; $r.Outputs = [ordered]@{ text_scale_percent = $v }; return $r }
function Invoke-ParsecDisplayDomainWaitTextScale { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()] $ExecutionResult) $e = if ($Arguments.Contains('text_scale_percent')) { [int] $Arguments.text_scale_percent } elseif ($Arguments.Contains('value')) { [int] $Arguments.value } else { [int] (Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult).text_scale_percent }; $o = Get-ParsecObservedState; $c = if ($o.Contains('font_scaling') -and $o.font_scaling.Contains('text_scale_percent')) { [int] $o.font_scaling.text_scale_percent } else { $null }; if ($c -ne $e) { return New-ParsecResult -Status 'Failed' -Message 'Text scale is still settling.' -Observed $o.font_scaling -Outputs @{ text_scale_percent = $e; observed_text_scale_percent = $c } -Errors @('ReadinessPending') }; return New-ParsecResult -Status 'Succeeded' -Message 'Text scale is ready.' -Observed $o.font_scaling -Outputs @{ text_scale_percent = $e } }
function Invoke-ParsecDisplayDomainVerifyTextScale { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()] $ExecutionResult) $e = if ($Arguments.Contains('text_scale_percent')) { [int] $Arguments.text_scale_percent } elseif ($Arguments.Contains('value')) { [int] $Arguments.value } else { [int] (Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult).text_scale_percent }; $o = Get-ParsecObservedState; $c = if ($o.Contains('font_scaling') -and $o.font_scaling.Contains('text_scale_percent')) { [int] $o.font_scaling.text_scale_percent } else { $null }; if ($c -ne $e) { return New-ParsecResult -Status 'Failed' -Message 'Text scale mismatch.' -Observed $o.font_scaling -Outputs @{ text_scale_percent = $e; observed_text_scale_percent = $c } -Errors @('TextScaleDrift') }; return New-ParsecResult -Status 'Succeeded' -Message 'Text scale matches.' -Observed $o.font_scaling -Outputs @{ text_scale_percent = $e } }
function Invoke-ParsecDisplayDomainResetTextScale { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()] $ExecutionResult) $s = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult; if ($null -eq $s -or -not $s.Contains('text_scale_percent')) { return New-ParsecResult -Status 'Failed' -Message 'Captured text scaling state does not include a resettable value.' -Errors @('MissingCapturedState') }; return Invoke-ParsecPersonalizationAdapter -Method 'SetTextScale' -Arguments @{ text_scale_percent = [int] $s.text_scale_percent } }

function Invoke-ParsecDisplayDomainApplyUiScale { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()] $ExecutionResult, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot)) $u = Resolve-ParsecDisplayDomainUiScaleExpectedValue -Arguments $Arguments -ExecutionResult $ExecutionResult; $d = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot; $r = Invoke-ParsecPersonalizationAdapter -Method 'SetUiScale' -Arguments @{ device_name = $d; ui_scale_percent = $u }; $a = if ($r.Outputs -and $r.Outputs.Contains('ui_scale_percent')) { [int] $r.Outputs.ui_scale_percent } else { $u }; $r.Requested = [ordered]@{ device_name = $d; ui_scale_percent = $u }; $r.Outputs = [ordered]@{ device_name = $d; ui_scale_percent = $a; requires_signout = if ($r.Outputs -and $r.Outputs.Contains('requires_signout')) { [bool] $r.Outputs.requires_signout } else { $false } }; return $r }
function Invoke-ParsecDisplayDomainWaitUiScale { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()] $ExecutionResult, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot)) $e = Resolve-ParsecDisplayDomainUiScaleExpectedValue -Arguments $Arguments -ExecutionResult $ExecutionResult; $o = Get-ParsecObservedState; $d = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot; $m = Get-ParsecObservedMonitor -ObservedState $o -DeviceName $d; if ($null -eq $m) { return New-ParsecResult -Status 'Failed' -Message \"Monitor '$d' not found during readiness probe.\" -Observed $o -Errors @('MonitorNotFound') }; $c = if ($m.display -is [System.Collections.IDictionary] -and $m.display.Contains('scale_percent')) { [int] $m.display.scale_percent } else { $null }; if ($c -ne $e) { return New-ParsecResult -Status 'Failed' -Message 'UI scale is still settling.' -Observed $m -Outputs @{ device_name = $d; ui_scale_percent = $e; observed_ui_scale_percent = $c; requires_signout = $false } -Errors @('ReadinessPending') }; return New-ParsecResult -Status 'Succeeded' -Message 'UI scale is ready.' -Observed $m -Outputs @{ device_name = $d; ui_scale_percent = $e; requires_signout = if ($ExecutionResult -and $ExecutionResult.Outputs -and $ExecutionResult.Outputs.Contains('requires_signout')) { [bool] $ExecutionResult.Outputs.requires_signout } else { $false } } }
function Invoke-ParsecDisplayDomainVerifyUiScale { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()] $ExecutionResult, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot)) $e = Resolve-ParsecDisplayDomainUiScaleExpectedValue -Arguments $Arguments -ExecutionResult $ExecutionResult; $o = Get-ParsecObservedState; $d = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot; $m = Get-ParsecObservedMonitor -ObservedState $o -DeviceName $d; if ($null -eq $m) { return New-ParsecResult -Status 'Failed' -Message \"Monitor '$d' not found.\" -Observed $o -Errors @('MonitorNotFound') }; $c = if ($m.display -is [System.Collections.IDictionary] -and $m.display.Contains('scale_percent')) { [int] $m.display.scale_percent } else { $null }; if ($c -ne $e) { return New-ParsecResult -Status 'Failed' -Message 'UI scale mismatch.' -Observed $m -Outputs @{ device_name = $d; ui_scale_percent = $e; observed_ui_scale_percent = $c; requires_signout = $false } -Errors @('UiScaleDrift') }; return New-ParsecResult -Status 'Succeeded' -Message 'UI scale matches.' -Observed $m -Outputs @{ device_name = $d; ui_scale_percent = $e; requires_signout = if ($ExecutionResult -and $ExecutionResult.Outputs -and $ExecutionResult.Outputs.Contains('requires_signout')) { [bool] $ExecutionResult.Outputs.requires_signout } else { $false } } }
function Invoke-ParsecDisplayDomainResetUiScale { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()] $ExecutionResult) $s = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult; if ($null -eq $s -or -not $s.Contains('ui_scale_percent')) { return New-ParsecResult -Status 'Failed' -Message 'Captured UI scaling state does not include a resettable value.' -Errors @('MissingCapturedState') }; return Invoke-ParsecPersonalizationAdapter -Method 'SetUiScale' -Arguments @{ device_name = if ($s.Contains('device_name')) { [string] $s.device_name } else { $null }; ui_scale_percent = [int] $s.ui_scale_percent } }

function Invoke-ParsecDisplayDomainCaptureSnapshot { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot), [Parameter()][System.Collections.IDictionary] $RunState = @{}) $n = Resolve-ParsecSnapshotName -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState -UseDefaultCaptureName; $o = Get-ParsecObservedState; $s = [ordered]@{ schema_version = 1; name = $n; source = 'capture'; captured_at = [DateTimeOffset]::UtcNow.ToString('o'); display = $o }; $p = Save-ParsecSnapshotDocument -Name $n -SnapshotDocument $s -StateRoot $StateRoot; $RunState.active_snapshot = $n; return New-ParsecResult -Status 'Succeeded' -Message \"Captured snapshot '$n'.\" -Observed $o -Outputs @{ snapshot_name = $n; snapshot = $s; path = $p } }
function Invoke-ParsecDisplayDomainResetSnapshot { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot), [Parameter()][System.Collections.IDictionary] $RunState = @{}) $t = Get-ParsecSnapshotTarget -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState; $RunState.active_snapshot = $t.snapshot_name; return Invoke-ParsecSnapshotReset -SnapshotDocument $t.snapshot }
function Invoke-ParsecDisplayDomainVerifySnapshot { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot), [Parameter()][System.Collections.IDictionary] $RunState = @{}) $t = Get-ParsecSnapshotTarget -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState; $o = Get-ParsecObservedState; $v = Compare-ParsecDisplayState -TargetState $t.snapshot.display -ObservedState $o; $v.Outputs.snapshot_name = $t.snapshot_name; return $v }

function Invoke-ParsecDisplayDomainCaptureTopologySnapshot { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot), [Parameter()][System.Collections.IDictionary] $RunState = @{}) $n = Resolve-ParsecSnapshotName -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState -UseDefaultCaptureName; $o = Get-ParsecObservedState; $t = Get-ParsecDisplayTopologyCaptureState -ObservedState $o; $s = [ordered]@{ schema_version = 1; name = $n; source = 'capture'; captured_at = [DateTimeOffset]::UtcNow.ToString('o'); display = $t }; $p = Save-ParsecSnapshotDocument -Name $n -SnapshotDocument $s -StateRoot $StateRoot; $RunState.active_snapshot = $n; return New-ParsecResult -Status 'Succeeded' -Message \"Captured topology snapshot '$n'.\" -Observed $t -Outputs @{ snapshot_name = $n; snapshot = $s; captured_state = $t; path = $p } }
function Invoke-ParsecDisplayDomainResetTopologySnapshot { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot), [Parameter()][System.Collections.IDictionary] $RunState = @{}) $t = Get-ParsecSnapshotTarget -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState; $RunState.active_snapshot = $t.snapshot_name; return Invoke-ParsecDisplayTopologyReset -TopologyState $t.snapshot.display -SnapshotName $t.snapshot_name }
function Invoke-ParsecDisplayDomainVerifyTopologySnapshot { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot), [Parameter()][System.Collections.IDictionary] $RunState = @{}) $t = Get-ParsecSnapshotTarget -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState; $o = Get-ParsecObservedState; $v = Compare-ParsecDisplayTopologyState -TargetState $t.snapshot.display -ObservedState $o; $v.Outputs.snapshot_name = $t.snapshot_name; return $v }
