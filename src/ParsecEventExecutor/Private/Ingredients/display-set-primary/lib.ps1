function Get-ParsecIngredientOperations {
    return @{
        capture = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $observed = Get-ParsecObservedState
            $primary = @($observed.monitors) | Where-Object { $_.is_primary } | Select-Object -First 1
            $outputs = [ordered]@{ captured_state = [ordered]@{ primary_monitor = $primary } }
            if ($Arguments.ContainsKey('device_name')) { $outputs.captured_state.requested_monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $Arguments.device_name }
            New-ParsecResult -Status 'Succeeded' -Message 'Captured primary monitor state.' -Observed $outputs.captured_state -Outputs $outputs
        }
        apply = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            Invoke-ParsecDisplayAdapter -Method 'SetPrimary' -Arguments $Arguments
        }
        verify = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $observed = Get-ParsecObservedState
            $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $Arguments.device_name
            if ($null -eq $monitor) { return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' not found." }
            if (-not [bool] $monitor.is_primary) { return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' is not primary." -Observed $monitor }
            New-ParsecResult -Status 'Succeeded' -Message 'Monitor is primary.' -Observed $monitor
        }
        reset = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $capturedMonitor = Get-ParsecDisplayResetMonitorState -Arguments $Arguments -ExecutionResult $ExecutionResult -Preference 'primary'
            if ($null -eq $capturedMonitor) {
                return New-ParsecResult -Status 'Failed' -Message 'Captured primary-monitor state does not include a resettable value.' -Errors @('MissingCapturedState')
            }

            Invoke-ParsecDisplayAdapter -Method 'SetPrimary' -Arguments @{
                device_name = [string] $capturedMonitor.device_name
            }
        }
    }
}
