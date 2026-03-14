function Get-ParsecCapturedStateFromResult {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    if ($Arguments.ContainsKey('captured_state') -and $Arguments.captured_state -is [System.Collections.IDictionary]) {
        return ConvertTo-ParsecPlainObject -InputObject $Arguments.captured_state
    }

    if ($null -ne $ExecutionResult -and $ExecutionResult.Outputs -and $ExecutionResult.Outputs.captured_state) {
        return ConvertTo-ParsecPlainObject -InputObject $ExecutionResult.Outputs.captured_state
    }

    return $null
}

function Get-ParsecDisplayResetMonitorState {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $Preference = 'requested'
    )

    $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -eq $capturedState) {
        return $null
    }

    if ($Preference -eq 'primary' -and $capturedState.Contains('primary_monitor')) {
        return $capturedState.primary_monitor
    }

    if ($capturedState.Contains('requested_monitor')) {
        return $capturedState.requested_monitor
    }

    return $capturedState
}

function Get-ParsecObservedState {
    [CmdletBinding()]
    param()

    $privateRoot = Split-Path -Path $PSScriptRoot -Parent
    . (Join-Path -Path $privateRoot -ChildPath 'Domains\display\Platform.ps1')
    . (Join-Path -Path $privateRoot -ChildPath 'Domains\personalization\Platform.ps1')

    return Invoke-ParsecDisplayAdapter -Method 'GetObservedState'
}

function Get-ParsecObservedMonitor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ObservedState,

        [Parameter(Mandatory)]
        [string] $DeviceName
    )

    return @($ObservedState.monitors) | Where-Object { $_.device_name -eq $DeviceName } | Select-Object -First 1
}

function Resolve-ParsecDisplayTargetMonitor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ObservedState,

        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    if ($Arguments.ContainsKey('screen_id') -and $null -ne $Arguments.screen_id) {
        return Resolve-ParsecDisplayDomainMonitorByScreenId -ObservedState $ObservedState -ScreenId ([int] $Arguments.screen_id) -StateRoot $StateRoot
    }

    if ($Arguments.ContainsKey('device_name') -and -not [string]::IsNullOrWhiteSpace([string] $Arguments.device_name)) {
        return Get-ParsecObservedMonitor -ObservedState $ObservedState -DeviceName ([string] $Arguments.device_name)
    }

    if ($Arguments.ContainsKey('monitor_device_path') -and -not [string]::IsNullOrWhiteSpace([string] $Arguments.monitor_device_path)) {
        return @($ObservedState.monitors) | Where-Object { $_.monitor_device_path -eq [string] $Arguments.monitor_device_path } | Select-Object -First 1
    }

    return @($ObservedState.monitors) | Where-Object { $_.is_primary } | Select-Object -First 1
}

function Resolve-ParsecDisplayTargetDeviceName {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    if ($Arguments.ContainsKey('device_name') -and -not [string]::IsNullOrWhiteSpace([string] $Arguments.device_name)) {
        return [string] $Arguments.device_name
    }

    $observed = Get-ParsecDisplayDomainObservedState
    $targetMonitor = Resolve-ParsecDisplayTargetMonitor -ObservedState $observed -Arguments $Arguments -StateRoot $StateRoot
    if ($null -eq $targetMonitor) {
        throw 'Could not resolve a target display device.'
    }

    return [string] $targetMonitor.device_name
}

function Get-ParsecSupportedDisplayModes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $DeviceName
    )

    $adapter = Get-ParsecModuleVariableValue -Name 'ParsecDisplayAdapter'
    if ($null -ne $adapter -and $adapter.ContainsKey('GetSupportedModes')) {
        return @(Invoke-ParsecDisplayAdapter -Method 'GetSupportedModes' -Arguments @{ device_name = $DeviceName })
    }

    Initialize-ParsecDisplayInterop
    $modes = @([ParsecEventExecutor.DisplayNative]::GetDisplayModes($DeviceName))
    return @(
        foreach ($mode in $modes) {
            [ordered]@{
                width = [int] $mode.Width
                height = [int] $mode.Height
                bits_per_pel = [int] $mode.BitsPerPel
                refresh_rate_hz = [int] $mode.DisplayFrequency
                orientation = ConvertTo-ParsecOrientationName -Orientation ([int] $mode.Orientation)
            }
        }
    )
}

function Get-ParsecDisplayCaptureResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ObservedState,

        [Parameter()]
        [string] $DeviceName,

        [Parameter(Mandatory)]
        [string] $Domain
    )

    if ($DeviceName) {
        $monitor = Get-ParsecObservedMonitor -ObservedState $ObservedState -DeviceName $DeviceName
        if ($null -eq $monitor) {
            return New-ParsecResult -Status 'Failed' -Message "Monitor '$DeviceName' not found." -Observed $ObservedState -Errors @('MonitorNotFound')
        }

        return New-ParsecResult -Status 'Succeeded' -Message "Captured $Domain state for '$DeviceName'." -Observed $monitor -Outputs @{
            captured_state = $monitor
            device_name = $DeviceName
            domain = $Domain
        }
    }

    return New-ParsecResult -Status 'Succeeded' -Message "Captured $Domain state." -Observed $ObservedState -Outputs @{
        captured_state = $ObservedState
        domain = $Domain
    }
}
