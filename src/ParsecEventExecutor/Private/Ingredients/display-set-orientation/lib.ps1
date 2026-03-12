function Get-ParsecIngredientOperations {
    return @{
        capture = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $observed = Get-ParsecObservedState
            Get-ParsecDisplayCaptureResult -ObservedState $observed -DeviceName $Arguments.device_name -Domain 'display orientation'
        }
        apply = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            Invoke-ParsecDisplayAdapter -Method 'SetOrientation' -Arguments $Arguments
        }
        verify = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $observed = Get-ParsecObservedState
            $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $Arguments.device_name
            if ($null -eq $monitor) { return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' not found." }
            if ($monitor.orientation -ne $Arguments.orientation) { return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' orientation mismatch." -Observed $monitor }
            New-ParsecResult -Status 'Succeeded' -Message 'Monitor orientation matches.' -Observed $monitor
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
