function Resolve-ParsecThemeExpectation {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    $expected = if ($Arguments.Contains('mode')) { [string] $Arguments.mode } else { $null }
    return [ordered]@{
        app_mode = if ($Arguments.Contains('app_mode')) {
            [string] $Arguments.app_mode
        }
        elseif ($expected -and $expected -ne 'Custom') {
            $expected
        }
        else {
            $null
        }
        system_mode = if ($Arguments.Contains('system_mode')) {
            [string] $Arguments.system_mode
        }
        elseif ($expected -and $expected -ne 'Custom') {
            $expected
        }
        else {
            $null
        }
    }
}

function Get-ParsecThemeCaptureResult {
    [CmdletBinding()]
    param()

    $themeState = Invoke-ParsecPersonalizationAdapter -Method 'GetThemeState'
    return New-ParsecResult -Status 'Succeeded' -Message 'Captured theme state.' -Observed $themeState -Outputs @{
        captured_state = $themeState
    }
}

function Invoke-ParsecThemeApply {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    return Invoke-ParsecPersonalizationAdapter -Method 'SetThemeState' -Arguments $Arguments
}

function Invoke-ParsecThemeVerify {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    $observed = Invoke-ParsecPersonalizationAdapter -Method 'GetThemeState'
    $expected = Resolve-ParsecThemeExpectation -Arguments $Arguments

    if ($expected.app_mode -and $observed.app_mode -ne $expected.app_mode) {
        return New-ParsecResult -Status 'Failed' -Message 'Application theme mismatch.' -Observed $observed
    }

    if ($expected.system_mode -and $observed.system_mode -ne $expected.system_mode) {
        return New-ParsecResult -Status 'Failed' -Message 'System theme mismatch.' -Observed $observed
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Theme matches.' -Observed $observed
}

function Invoke-ParsecThemeReset {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    if ($Arguments.Contains('captured_state') -and $Arguments.captured_state -is [System.Collections.IDictionary]) {
        return Invoke-ParsecPersonalizationAdapter -Method 'SetThemeState' -Arguments @{
            theme_state = $Arguments.captured_state
        }
    }

    if ($null -ne $ExecutionResult -and $ExecutionResult.Outputs.captured_state) {
        return Invoke-ParsecPersonalizationAdapter -Method 'SetThemeState' -Arguments @{
            theme_state = $ExecutionResult.Outputs.captured_state
        }
    }

    return Invoke-ParsecPersonalizationAdapter -Method 'SetThemeState' -Arguments $Arguments
}

function Resolve-ParsecTextScaleExpectedValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    if ($Arguments.Contains('text_scale_percent')) {
        return [int] $Arguments.text_scale_percent
    }

    if ($Arguments.Contains('value')) {
        return [int] $Arguments.value
    }

    $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -ne $capturedState -and $capturedState.Contains('text_scale_percent')) {
        return [int] $capturedState.text_scale_percent
    }

    throw 'Text scale operation requires text_scale_percent or value.'
}

function Get-ParsecTextScaleCaptureResult {
    [CmdletBinding()]
    param()

    $observed = Get-ParsecDisplayDomainObservedState
    $textScalePercent = if ($observed.Contains('font_scaling') -and $observed.font_scaling.Contains('text_scale_percent')) {
        [int] $observed.font_scaling.text_scale_percent
    }
    else {
        $null
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Captured text scaling state.' -Observed @{
        text_scale_percent = $textScalePercent
    } -Outputs @{
        captured_state = @{
            text_scale_percent = $textScalePercent
        }
    }
}

function Invoke-ParsecTextScaleApply {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $textScalePercent = Resolve-ParsecTextScaleExpectedValue -Arguments $Arguments -ExecutionResult $ExecutionResult
    $result = Invoke-ParsecPersonalizationAdapter -Method 'SetTextScale' -Arguments @{
        text_scale_percent = $textScalePercent
    }
    $result.Requested = [ordered]@{
        text_scale_percent = $textScalePercent
    }
    $result.Outputs = [ordered]@{
        text_scale_percent = $textScalePercent
    }
    return $result
}

function Invoke-ParsecTextScaleWait {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $expected = Resolve-ParsecTextScaleExpectedValue -Arguments $Arguments -ExecutionResult $ExecutionResult
    $observed = Get-ParsecDisplayDomainObservedState
    $current = if ($observed.Contains('font_scaling') -and $observed.font_scaling.Contains('text_scale_percent')) {
        [int] $observed.font_scaling.text_scale_percent
    }
    else {
        $null
    }

    if ($current -ne $expected) {
        return New-ParsecResult -Status 'Failed' -Message 'Text scale is still settling.' -Observed $observed.font_scaling -Outputs @{
            text_scale_percent = $expected
            observed_text_scale_percent = $current
        } -Errors @('ReadinessPending')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Text scale is ready.' -Observed $observed.font_scaling -Outputs @{
        text_scale_percent = $expected
    }
}

function Invoke-ParsecTextScaleVerify {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $expected = Resolve-ParsecTextScaleExpectedValue -Arguments $Arguments -ExecutionResult $ExecutionResult
    $observed = Get-ParsecDisplayDomainObservedState
    $current = if ($observed.Contains('font_scaling') -and $observed.font_scaling.Contains('text_scale_percent')) {
        [int] $observed.font_scaling.text_scale_percent
    }
    else {
        $null
    }

    if ($current -ne $expected) {
        return New-ParsecResult -Status 'Failed' -Message 'Text scale mismatch.' -Observed $observed.font_scaling -Outputs @{
            text_scale_percent = $expected
            observed_text_scale_percent = $current
        } -Errors @('TextScaleDrift')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Text scale matches.' -Observed $observed.font_scaling -Outputs @{
        text_scale_percent = $expected
    }
}

function Invoke-ParsecTextScaleReset {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -eq $capturedState -or -not $capturedState.Contains('text_scale_percent')) {
        return New-ParsecResult -Status 'Failed' -Message 'Captured text scaling state does not include a resettable value.' -Errors @('MissingCapturedState')
    }

    return Invoke-ParsecPersonalizationAdapter -Method 'SetTextScale' -Arguments @{
        text_scale_percent = [int] $capturedState.text_scale_percent
    }
}

function Resolve-ParsecUiScaleExpectedValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    if ($null -ne $ExecutionResult -and $ExecutionResult.Outputs -and $ExecutionResult.Outputs.Contains('ui_scale_percent')) {
        return [int] $ExecutionResult.Outputs.ui_scale_percent
    }

    if ($Arguments.Contains('ui_scale_percent')) {
        return [int] $Arguments.ui_scale_percent
    }

    if ($Arguments.Contains('scale_percent')) {
        return [int] $Arguments.scale_percent
    }

    if ($Arguments.Contains('value')) {
        return [int] $Arguments.value
    }

    $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -ne $capturedState -and $capturedState.Contains('ui_scale_percent')) {
        return [int] $capturedState.ui_scale_percent
    }

    throw 'UI scale operation requires ui_scale_percent, scale_percent, or value.'
}

function Get-ParsecUiScaleCaptureResult {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $observed = Get-ParsecDisplayDomainObservedState
    $targetMonitor = Resolve-ParsecDisplayTargetMonitor -ObservedState $observed -Arguments $Arguments -StateRoot $StateRoot
    if ($null -eq $targetMonitor) {
        return New-ParsecResult -Status 'Failed' -Message 'Target monitor could not be resolved.' -Observed $observed -Errors @('MonitorNotFound')
    }

    $uiScalePercent = if ($targetMonitor.display -is [System.Collections.IDictionary] -and $targetMonitor.display.Contains('scale_percent')) {
        [int] $targetMonitor.display.scale_percent
    }
    else {
        $null
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Captured UI scaling state.' -Observed @{
        device_name = [string] $targetMonitor.device_name
        ui_scale_percent = $uiScalePercent
    } -Outputs @{
        captured_state = @{
            device_name = [string] $targetMonitor.device_name
            ui_scale_percent = $uiScalePercent
        }
    }
}

function Invoke-ParsecUiScaleApply {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $uiScalePercent = Resolve-ParsecUiScaleExpectedValue -Arguments $Arguments -ExecutionResult $ExecutionResult
    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $result = Invoke-ParsecPersonalizationAdapter -Method 'SetUiScale' -Arguments @{
        device_name = $deviceName
        ui_scale_percent = $uiScalePercent
    }
    $appliedUiScalePercent = if ($result.Outputs -and $result.Outputs.Contains('ui_scale_percent')) {
        [int] $result.Outputs.ui_scale_percent
    }
    else {
        $uiScalePercent
    }
    $result.Requested = [ordered]@{
        device_name = $deviceName
        ui_scale_percent = $uiScalePercent
    }
    $result.Outputs = [ordered]@{
        device_name = $deviceName
        ui_scale_percent = $appliedUiScalePercent
        requires_signout = if ($result.Outputs -and $result.Outputs.Contains('requires_signout')) { [bool] $result.Outputs.requires_signout } else { $false }
    }
    return $result
}

function Invoke-ParsecUiScaleWait {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $expected = Resolve-ParsecUiScaleExpectedValue -Arguments $Arguments -ExecutionResult $ExecutionResult
    $observed = Get-ParsecDisplayDomainObservedState
    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $deviceName
    if ($null -eq $monitor) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' not found during readiness probe." -Observed $observed -Errors @('MonitorNotFound')
    }

    $current = if ($monitor.display -is [System.Collections.IDictionary] -and $monitor.display.Contains('scale_percent')) {
        [int] $monitor.display.scale_percent
    }
    else {
        $null
    }

    if ($current -ne $expected) {
        return New-ParsecResult -Status 'Failed' -Message 'UI scale is still settling.' -Observed $monitor -Outputs @{
            device_name = $deviceName
            ui_scale_percent = $expected
            observed_ui_scale_percent = $current
            requires_signout = $false
        } -Errors @('ReadinessPending')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'UI scale is ready.' -Observed $monitor -Outputs @{
        device_name = $deviceName
        ui_scale_percent = $expected
        requires_signout = if ($ExecutionResult -and $ExecutionResult.Outputs -and $ExecutionResult.Outputs.Contains('requires_signout')) { [bool] $ExecutionResult.Outputs.requires_signout } else { $false }
    }
}

function Invoke-ParsecUiScaleVerify {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $expected = Resolve-ParsecUiScaleExpectedValue -Arguments $Arguments -ExecutionResult $ExecutionResult
    $observed = Get-ParsecDisplayDomainObservedState
    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $deviceName
    if ($null -eq $monitor) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' not found." -Observed $observed -Errors @('MonitorNotFound')
    }

    $current = if ($monitor.display -is [System.Collections.IDictionary] -and $monitor.display.Contains('scale_percent')) {
        [int] $monitor.display.scale_percent
    }
    else {
        $null
    }

    if ($current -ne $expected) {
        return New-ParsecResult -Status 'Failed' -Message 'UI scale mismatch.' -Observed $monitor -Outputs @{
            device_name = $deviceName
            ui_scale_percent = $expected
            observed_ui_scale_percent = $current
            requires_signout = $false
        } -Errors @('UiScaleDrift')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'UI scale matches.' -Observed $monitor -Outputs @{
        device_name = $deviceName
        ui_scale_percent = $expected
        requires_signout = if ($ExecutionResult -and $ExecutionResult.Outputs -and $ExecutionResult.Outputs.Contains('requires_signout')) { [bool] $ExecutionResult.Outputs.requires_signout } else { $false }
    }
}

function Invoke-ParsecUiScaleReset {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -eq $capturedState -or -not $capturedState.Contains('ui_scale_percent')) {
        return New-ParsecResult -Status 'Failed' -Message 'Captured UI scaling state does not include a resettable value.' -Errors @('MissingCapturedState')
    }

    return Invoke-ParsecPersonalizationAdapter -Method 'SetUiScale' -Arguments @{
        device_name = if ($capturedState.Contains('device_name')) { [string] $capturedState.device_name } else { $null }
        ui_scale_percent = [int] $capturedState.ui_scale_percent
    }
}
