function Get-ParsecIngredientOperations {
    return @{
        capture = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $observed = Get-ParsecObservedState
            $targetMonitor = Resolve-ParsecDisplayTargetMonitor -ObservedState $observed -Arguments $Arguments -StateRoot $StateRoot
            if ($null -eq $targetMonitor) {
                return New-ParsecResult -Status 'Failed' -Message 'Target monitor could not be resolved.' -Observed $observed -Errors @('MonitorNotFound')
            }

            Get-ParsecDisplayCaptureResult -ObservedState $observed -DeviceName ([string] $targetMonitor.device_name) -Domain 'display resolution'
        }
        apply   = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
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
                    device_name            = $deviceName
                    width                  = $requestedWidth
                    height                 = $requestedHeight
                    supported_mode_count   = $supportedModeCount
                    supported_modes_sample = @($supportedModes | Select-Object -First 10)
                } -Errors @('UnsupportedResolution')
            }

            $result = Invoke-ParsecDisplayAdapter -Method 'SetResolution' -Arguments @{
                device_name = $deviceName
                width       = $requestedWidth
                height      = $requestedHeight
            }
            $result.Requested = [ordered]@{
                device_name = $deviceName
                width       = $requestedWidth
                height      = $requestedHeight
            }
            $result.Outputs = [ordered]@{
                device_name            = $deviceName
                width                  = $requestedWidth
                height                 = $requestedHeight
                supported_mode_count   = $supportedModeCount
                supported_modes_sample = @($supportedModes | Select-Object -First 10)
            }
            return $result
        }
        verify  = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $observed = Get-ParsecObservedState
            $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
            $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $deviceName
            if ($null -eq $monitor) {
                return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' not found." -Observed $observed -Errors @('MonitorNotFound')
            }

            if ($monitor.bounds.width -ne [int] $Arguments.width -or $monitor.bounds.height -ne [int] $Arguments.height) {
                $supportedModes = @(Get-ParsecSupportedDisplayModes -DeviceName $deviceName)
                return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' resolution mismatch." -Observed $monitor -Outputs @{
                    device_name            = $deviceName
                    width                  = [int] $Arguments.width
                    height                 = [int] $Arguments.height
                    supported_mode_count   = @($supportedModes).Count
                    supported_modes_sample = @($supportedModes | Select-Object -First 10)
                } -Errors @('ResolutionDrift')
            }

            New-ParsecResult -Status 'Succeeded' -Message 'Monitor resolution matches.' -Observed $monitor -Outputs @{
                device_name = $deviceName
                width       = [int] $Arguments.width
                height      = [int] $Arguments.height
            }
        }
        reset   = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $capturedMonitor = Get-ParsecDisplayResetMonitorState -Arguments $Arguments -ExecutionResult $ExecutionResult
            if ($null -eq $capturedMonitor -or -not $capturedMonitor.Contains('bounds')) {
                return New-ParsecResult -Status 'Failed' -Message 'Captured resolution state does not include a resettable value.' -Errors @('MissingCapturedState')
            }

            Invoke-ParsecDisplayAdapter -Method 'SetResolution' -Arguments @{
                device_name = [string] $capturedMonitor.device_name
                width       = [int] $capturedMonitor.bounds.width
                height      = [int] $capturedMonitor.bounds.height
            }
        }
    }
}
