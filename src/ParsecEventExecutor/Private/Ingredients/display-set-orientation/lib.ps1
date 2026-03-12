function Get-ParsecIngredientOperations {
    return @{
        capture = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $observed = Get-ParsecObservedState
            $targetMonitor = Resolve-ParsecDisplayTargetMonitor -ObservedState $observed -Arguments $Arguments -StateRoot $StateRoot
            if ($null -eq $targetMonitor) {
                return New-ParsecResult -Status 'Failed' -Message 'Target monitor could not be resolved.' -Observed $observed -Errors @('MonitorNotFound')
            }

            Get-ParsecDisplayCaptureResult -ObservedState $observed -DeviceName ([string] $targetMonitor.device_name) -Domain 'display orientation'
        }
        apply = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
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
        wait = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
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

            New-ParsecResult -Status 'Succeeded' -Message 'Monitor orientation is ready.' -Observed $monitor -Outputs @{
                device_name = $deviceName
                orientation = $expectedOrientation
            }
        }
        verify = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
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

            New-ParsecResult -Status 'Succeeded' -Message 'Monitor orientation matches.' -Observed $monitor -Outputs @{
                device_name = $deviceName
                orientation = [string] $Arguments.orientation
            }
        }
        reset = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $capturedMonitor = Get-ParsecDisplayResetMonitorState -Arguments $Arguments -ExecutionResult $ExecutionResult
            if ($null -eq $capturedMonitor -or -not $capturedMonitor.Contains('orientation') -or $capturedMonitor.orientation -eq 'Unknown') {
                return New-ParsecResult -Status 'Failed' -Message 'Captured orientation state does not include a resettable value.' -Errors @('MissingCapturedState')
            }

            Invoke-ParsecDisplayAdapter -Method 'SetOrientation' -Arguments @{
                device_name = [string] $capturedMonitor.device_name
                orientation = [string] $capturedMonitor.orientation
            }
        }
    }
}
