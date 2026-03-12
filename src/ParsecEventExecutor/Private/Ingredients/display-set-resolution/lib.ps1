function Get-ParsecIngredientOperations {
    return @{
        capture = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $observed = Get-ParsecObservedState
            Get-ParsecDisplayCaptureResult -ObservedState $observed -DeviceName $Arguments.device_name -Domain 'display resolution'
        }
        apply = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            Invoke-ParsecDisplayAdapter -Method 'SetResolution' -Arguments $Arguments
        }
        verify = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $observed = Get-ParsecObservedState
            $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $Arguments.device_name
            if ($null -eq $monitor) { return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' not found." }
            if ($monitor.bounds.width -ne $Arguments.width -or $monitor.bounds.height -ne $Arguments.height) { return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' resolution mismatch." -Observed $monitor }
            New-ParsecResult -Status 'Succeeded' -Message 'Monitor resolution matches.' -Observed $monitor
        }
        reset = {
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
