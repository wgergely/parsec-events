function Get-ParsecIngredientOperations {
    return @{
        capture = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $observed = Get-ParsecObservedState
            $targetMonitor = Resolve-ParsecDisplayTargetMonitor -ObservedState $observed -Arguments $Arguments -StateRoot $StateRoot
            if ($null -eq $targetMonitor) {
                return New-ParsecResult -Status 'Failed' -Message 'Target monitor could not be resolved.' -Observed $observed -Errors @('MonitorNotFound')
            }
            $uiScalePercent = if ($targetMonitor.display -is [System.Collections.IDictionary] -and $targetMonitor.display.Contains('scale_percent')) { [int] $targetMonitor.display.scale_percent } else { $null }

            New-ParsecResult -Status 'Succeeded' -Message 'Captured UI scaling state.' -Observed @{
                device_name = [string] $targetMonitor.device_name
                ui_scale_percent = $uiScalePercent
            } -Outputs @{
                captured_state = @{
                    device_name = [string] $targetMonitor.device_name
                    ui_scale_percent = $uiScalePercent
                }
            }
        }
        apply = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $uiScalePercent = if ($Arguments.Contains('ui_scale_percent')) {
                [int] $Arguments.ui_scale_percent
            }
            elseif ($Arguments.Contains('scale_percent')) {
                [int] $Arguments.scale_percent
            }
            elseif ($Arguments.Contains('value')) {
                [int] $Arguments.value
            }
            else {
                $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
                if ($null -ne $capturedState -and $capturedState.Contains('ui_scale_percent')) {
                    [int] $capturedState.ui_scale_percent
                }
                else {
                    throw 'UI scale operation requires ui_scale_percent, scale_percent, or value.'
                }
            }

            $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
            $result = Invoke-ParsecPersonalizationAdapter -Method 'SetUiScale' -Arguments @{
                device_name = $deviceName
                ui_scale_percent = $uiScalePercent
            }
            $result.Requested = [ordered]@{
                device_name = $deviceName
                ui_scale_percent = $uiScalePercent
            }
            $result.Outputs = [ordered]@{
                device_name = $deviceName
                ui_scale_percent = $uiScalePercent
                requires_signout = if ($result.Outputs -and $result.Outputs.Contains('requires_signout')) { [bool] $result.Outputs.requires_signout } else { $false }
            }
            return $result
        }
        wait = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $expected = if ($Arguments.Contains('ui_scale_percent')) {
                [int] $Arguments.ui_scale_percent
            }
            elseif ($Arguments.Contains('scale_percent')) {
                [int] $Arguments.scale_percent
            }
            elseif ($Arguments.Contains('value')) {
                [int] $Arguments.value
            }
            else {
                $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
                if ($null -ne $capturedState -and $capturedState.Contains('ui_scale_percent')) {
                    [int] $capturedState.ui_scale_percent
                }
                else {
                    throw 'UI scale operation requires ui_scale_percent, scale_percent, or value.'
                }
            }
            $observed = Get-ParsecObservedState
            $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
            $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $deviceName
            if ($null -eq $monitor) {
                return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' not found during readiness probe." -Observed $observed -Errors @('MonitorNotFound')
            }
            $current = if ($monitor.display -is [System.Collections.IDictionary] -and $monitor.display.Contains('scale_percent')) { [int] $monitor.display.scale_percent } else { $null }

            if ($current -ne $expected) {
                return New-ParsecResult -Status 'Failed' -Message 'UI scale is still settling.' -Observed $monitor -Outputs @{
                    device_name = $deviceName
                    ui_scale_percent = $expected
                    observed_ui_scale_percent = $current
                    requires_signout = $false
                } -Errors @('ReadinessPending')
            }

            New-ParsecResult -Status 'Succeeded' -Message 'UI scale is ready.' -Observed $monitor -Outputs @{
                device_name = $deviceName
                ui_scale_percent = $expected
                requires_signout = if ($ExecutionResult -and $ExecutionResult.Outputs -and $ExecutionResult.Outputs.Contains('requires_signout')) { [bool] $ExecutionResult.Outputs.requires_signout } else { $false }
            }
        }
        verify = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $expected = if ($Arguments.Contains('ui_scale_percent')) {
                [int] $Arguments.ui_scale_percent
            }
            elseif ($Arguments.Contains('scale_percent')) {
                [int] $Arguments.scale_percent
            }
            elseif ($Arguments.Contains('value')) {
                [int] $Arguments.value
            }
            else {
                $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
                if ($null -ne $capturedState -and $capturedState.Contains('ui_scale_percent')) {
                    [int] $capturedState.ui_scale_percent
                }
                else {
                    throw 'UI scale operation requires ui_scale_percent, scale_percent, or value.'
                }
            }
            $observed = Get-ParsecObservedState
            $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
            $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $deviceName
            if ($null -eq $monitor) {
                return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' not found." -Observed $observed -Errors @('MonitorNotFound')
            }
            $current = if ($monitor.display -is [System.Collections.IDictionary] -and $monitor.display.Contains('scale_percent')) { [int] $monitor.display.scale_percent } else { $null }

            if ($current -ne $expected) {
                return New-ParsecResult -Status 'Failed' -Message 'UI scale mismatch.' -Observed $monitor -Outputs @{
                    device_name = $deviceName
                    ui_scale_percent = $expected
                    observed_ui_scale_percent = $current
                    requires_signout = $false
                } -Errors @('UiScaleDrift')
            }

            New-ParsecResult -Status 'Succeeded' -Message 'UI scale matches.' -Observed $monitor -Outputs @{
                device_name = $deviceName
                ui_scale_percent = $expected
                requires_signout = if ($ExecutionResult -and $ExecutionResult.Outputs -and $ExecutionResult.Outputs.Contains('requires_signout')) { [bool] $ExecutionResult.Outputs.requires_signout } else { $false }
            }
        }
        reset = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
            if ($null -eq $capturedState -or -not $capturedState.Contains('ui_scale_percent')) {
                return New-ParsecResult -Status 'Failed' -Message 'Captured UI scaling state does not include a resettable value.' -Errors @('MissingCapturedState')
            }

            Invoke-ParsecPersonalizationAdapter -Method 'SetUiScale' -Arguments @{
                device_name = if ($capturedState.Contains('device_name')) { [string] $capturedState.device_name } else { $null }
                ui_scale_percent = [int] $capturedState.ui_scale_percent
            }
        }
    }
}
