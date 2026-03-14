function Get-ParsecSoundDomainAdapter {
    [CmdletBinding()]
    [OutputType([object])]
    param()

    return Get-ParsecModuleVariableValue -Name 'ParsecSoundAdapter'
}

function Get-ParsecSoundPlaybackDevice {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary[]])]
    [OutputType([System.Object[]])]
    param()

    $adapter = Get-ParsecSoundDomainAdapter
    if ($null -ne $adapter -and $adapter.ContainsKey('GetPlaybackDevices')) {
        return @(& $adapter.GetPlaybackDevices)
    }

    $audioEndpoints = @()
    try {
        Add-Type -AssemblyName System.Runtime.InteropServices -ErrorAction SilentlyContinue
        $mmDevices = Get-CimInstance -Namespace 'root\Microsoft\Windows\Audio' -ClassName 'MSFT_AudioDevice' -ErrorAction SilentlyContinue
        if ($null -ne $mmDevices) {
            foreach ($device in @($mmDevices)) {
                $audioEndpoints += [ordered]@{
                    id = [string] $device.DeviceId
                    name = [string] $device.Name
                    is_default = [bool] $device.IsDefault
                    type = [string] $device.Type
                    status = [string] $device.Status
                }
            }

            return $audioEndpoints
        }
    }
    catch {
        Write-Verbose "MSFT_AudioDevice WMI class unavailable, falling back to AudioDeviceCmdlets module."
    }

    # Fallback: Use AudioDeviceCmdlets module if available
    if (Get-Command -Name 'Get-AudioDevice' -ErrorAction SilentlyContinue) {
        $playbackDevices = @(Get-AudioDevice -List | Where-Object { $_.Type -eq 'Playback' })
        foreach ($device in $playbackDevices) {
            $audioEndpoints += [ordered]@{
                id = [string] $device.ID
                name = [string] $device.Name
                is_default = [bool] $device.Default
                type = 'Playback'
                status = 'Active'
            }
        }

        return $audioEndpoints
    }

    return @()
}

function Get-ParsecSoundDefaultPlaybackDevice {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    $adapter = Get-ParsecSoundDomainAdapter
    if ($null -ne $adapter -and $adapter.ContainsKey('GetDefaultPlaybackDevice')) {
        return & $adapter.GetDefaultPlaybackDevice
    }

    $devices = @(Get-ParsecSoundPlaybackDevice)
    $defaultDevice = @($devices | Where-Object { $_.is_default }) | Select-Object -First 1
    if ($null -ne $defaultDevice) {
        return $defaultDevice
    }

    # If no default found but devices exist, return the first
    if ($devices.Count -gt 0) {
        return $devices[0]
    }

    return $null
}

function Set-ParsecSoundDefaultPlaybackDevice {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Arguments
    )

    $adapter = Get-ParsecSoundDomainAdapter
    if ($null -ne $adapter -and $adapter.ContainsKey('SetDefaultPlaybackDevice')) {
        return & $adapter.SetDefaultPlaybackDevice $Arguments
    }

    $deviceId = if ($Arguments.ContainsKey('device_id')) { [string] $Arguments.device_id } else { $null }
    $deviceName = if ($Arguments.ContainsKey('device_name')) { [string] $Arguments.device_name } else { $null }

    if ([string]::IsNullOrWhiteSpace($deviceId) -and [string]::IsNullOrWhiteSpace($deviceName)) {
        return New-ParsecResult -Status 'Failed' -Message 'Either device_id or device_name is required to set the default playback device.' -Errors @('MissingArgument')
    }

    $targetDescription = if (-not [string]::IsNullOrWhiteSpace($deviceId)) { "device '$deviceId'" } else { "device '$deviceName'" }
    if (-not $PSCmdlet.ShouldProcess($targetDescription, 'Set default playback device')) {
        return New-ParsecResult -Status 'Skipped' -Message 'Operation skipped by ShouldProcess.'
    }

    # Try AudioDeviceCmdlets module
    if (Get-Command -Name 'Set-AudioDevice' -ErrorAction SilentlyContinue) {
        if (-not [string]::IsNullOrWhiteSpace($deviceId)) {
            Set-AudioDevice -ID $deviceId
        }
        else {
            $targetDevice = Get-AudioDevice -List | Where-Object { $_.Type -eq 'Playback' -and $_.Name -eq $deviceName } | Select-Object -First 1
            if ($null -eq $targetDevice) {
                return New-ParsecResult -Status 'Failed' -Message "Playback device '$deviceName' not found." -Errors @('DeviceNotFound')
            }

            Set-AudioDevice -ID $targetDevice.ID
        }

        $currentDefault = Get-ParsecSoundDefaultPlaybackDevice
        return New-ParsecResult -Status 'Succeeded' -Message "Set default playback device." -Observed @{
            device_id = if ($null -ne $currentDefault) { [string] $currentDefault.id } else { $null }
            device_name = if ($null -ne $currentDefault) { [string] $currentDefault.name } else { $null }
        } -Outputs @{
            device_id = if ($null -ne $currentDefault) { [string] $currentDefault.id } else { $null }
            device_name = if ($null -ne $currentDefault) { [string] $currentDefault.name } else { $null }
        }
    }

    return New-ParsecResult -Status 'Failed' -Message 'No supported audio device management backend is available. Install AudioDeviceCmdlets module.' -Errors @('CapabilityUnavailable')
}

function Invoke-ParsecSoundDomain {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string] $Method,

        [Parameter()]
        [hashtable] $Arguments = @{}
    )

    switch ($Method) {
        'Capture' {
            $currentDevice = Get-ParsecSoundDefaultPlaybackDevice
            if ($null -eq $currentDevice) {
                return New-ParsecResult -Status 'Succeeded' -Message 'No playback device detected.' -Observed @{
                    has_device = $false
                } -Outputs @{
                    captured_state = @{
                        has_device = $false
                    }
                }
            }

            return New-ParsecResult -Status 'Succeeded' -Message "Captured default playback device: $([string] $currentDevice.name)." -Observed @{
                has_device = $true
                device_id = [string] $currentDevice.id
                device_name = [string] $currentDevice.name
                is_default = $true
            } -Outputs @{
                captured_state = @{
                    has_device = $true
                    device_id = [string] $currentDevice.id
                    device_name = [string] $currentDevice.name
                }
            }
        }
        'SetPlaybackDevice' {
            return Set-ParsecSoundDefaultPlaybackDevice -Arguments $Arguments
        }
        'ResetPlaybackDevice' {
            $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $null
            if ($null -eq $capturedState -or -not $capturedState.Contains('has_device')) {
                return New-ParsecResult -Status 'Failed' -Message 'Captured sound state does not include a resettable device.' -Errors @('MissingCapturedState')
            }

            if (-not [bool] $capturedState.has_device) {
                return New-ParsecResult -Status 'Succeeded' -Message 'No playback device was captured; nothing to reset.'
            }

            $resetArgs = @{}
            if ($capturedState.Contains('device_id') -and -not [string]::IsNullOrWhiteSpace([string] $capturedState.device_id)) {
                $resetArgs['device_id'] = [string] $capturedState.device_id
            }

            if ($capturedState.Contains('device_name') -and -not [string]::IsNullOrWhiteSpace([string] $capturedState.device_name)) {
                $resetArgs['device_name'] = [string] $capturedState.device_name
            }

            return Set-ParsecSoundDefaultPlaybackDevice -Arguments $resetArgs
        }
        'VerifyPlaybackDevice' {
            $currentDevice = Get-ParsecSoundDefaultPlaybackDevice
            $targetId = if ($Arguments.ContainsKey('device_id')) { [string] $Arguments.device_id } else { $null }
            $targetName = if ($Arguments.ContainsKey('device_name')) { [string] $Arguments.device_name } else { $null }

            if ($null -eq $currentDevice) {
                return New-ParsecResult -Status 'Failed' -Message 'No playback device detected for verification.' -Errors @('NoPlaybackDevice')
            }

            $match = $false
            if (-not [string]::IsNullOrWhiteSpace($targetId)) {
                $match = [string] $currentDevice.id -eq $targetId
            }
            elseif (-not [string]::IsNullOrWhiteSpace($targetName)) {
                $match = [string] $currentDevice.name -eq $targetName
            }
            else {
                $match = [bool] $currentDevice.is_default
            }

            if ($match) {
                return New-ParsecResult -Status 'Succeeded' -Message "Default playback device is '$([string] $currentDevice.name)'." -Observed @{
                    device_id = [string] $currentDevice.id
                    device_name = [string] $currentDevice.name
                    is_default = $true
                }
            }

            return New-ParsecResult -Status 'Failed' -Message "Default playback device is '$([string] $currentDevice.name)', expected '$($targetName ?? $targetId)'." -Observed @{
                device_id = [string] $currentDevice.id
                device_name = [string] $currentDevice.name
                is_default = [bool] $currentDevice.is_default
            }
        }
        'GetPlaybackDevices' {
            $devices = @(Get-ParsecSoundPlaybackDevice)
            return New-ParsecResult -Status 'Succeeded' -Message "Found $($devices.Count) playback device(s)." -Observed @{
                devices = $devices
                count = $devices.Count
            }
        }
        default {
            throw "Sound domain method '$Method' is not available."
        }
    }
}
