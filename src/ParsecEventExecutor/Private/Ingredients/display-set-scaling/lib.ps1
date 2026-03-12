function Get-ParsecIngredientOperations {
    return @{
        capture = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $observed = Get-ParsecObservedState
            if ($Arguments.ContainsKey('device_name')) {
                $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $Arguments.device_name
                if ($null -eq $monitor) { return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' not found." -Observed $observed -Errors @('MonitorNotFound') }
                $scalePercent = if ($monitor.Contains('display') -and $monitor.display.Contains('scale_percent')) { $monitor.display.scale_percent } else { $null }
                $effectiveDpiX = if ($monitor.Contains('display') -and $monitor.display.Contains('effective_dpi_x')) { $monitor.display.effective_dpi_x } else { $null }
                $effectiveDpiY = if ($monitor.Contains('display') -and $monitor.display.Contains('effective_dpi_y')) { $monitor.display.effective_dpi_y } else { $null }
                $textScalePercent = if ($observed.Contains('font_scaling') -and $observed.font_scaling.Contains('text_scale_percent')) { $observed.font_scaling.text_scale_percent } else { $null }
                return New-ParsecResult -Status 'Succeeded' -Message "Captured display scaling state for '$($Arguments.device_name)'." -Observed @{ device_name = $monitor.device_name; scale_percent = $scalePercent; effective_dpi_x = $effectiveDpiX; effective_dpi_y = $effectiveDpiY; text_scale_percent = $textScalePercent } -Outputs @{ captured_state = @{ device_name = $monitor.device_name; scale_percent = $scalePercent; effective_dpi_x = $effectiveDpiX; effective_dpi_y = $effectiveDpiY; text_scale_percent = $textScalePercent } }
            }
            New-ParsecResult -Status 'Succeeded' -Message 'Captured display scaling state.' -Observed @{ scaling = $observed.scaling; font_scaling = $observed.font_scaling } -Outputs @{ captured_state = @{ scaling = $observed.scaling; font_scaling = $observed.font_scaling; ui_scale_percent = $observed.scaling.ui_scale_percent; text_scale_percent = $observed.font_scaling.text_scale_percent } }
        }
        apply = { param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition) Invoke-ParsecDisplayAdapter -Method 'SetScaling' -Arguments $Arguments }
        verify = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $observed = Get-ParsecObservedState
            $currentValue = $null
            $expectedValue = if ($Arguments.ContainsKey('text_scale_percent')) { [int] $Arguments.text_scale_percent } elseif ($Arguments.ContainsKey('ui_scale_percent')) { [int] $Arguments.ui_scale_percent } elseif ($Arguments.ContainsKey('scale_percent')) { [int] $Arguments.scale_percent } elseif ($Arguments.ContainsKey('value')) { [int] $Arguments.value } else { $null }
            if ($Arguments.ContainsKey('device_name')) {
                $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $Arguments.device_name
                if ($null -ne $monitor -and $monitor.Contains('display') -and $monitor.display.Contains('scale_percent')) { $currentValue = $monitor.display.scale_percent }
            } elseif ($Arguments.ContainsKey('text_scale_percent') -and $observed.Contains('font_scaling') -and $observed.font_scaling.Contains('text_scale_percent')) { $currentValue = $observed.font_scaling.text_scale_percent } elseif (($Arguments.ContainsKey('ui_scale_percent') -or $Arguments.ContainsKey('scale_percent') -or $Arguments.ContainsKey('value')) -and $observed.scaling.Contains('ui_scale_percent')) { $currentValue = $observed.scaling.ui_scale_percent } elseif ($observed.scaling.Contains('text_scale_percent')) { $currentValue = $observed.scaling.text_scale_percent }
            if ($null -eq $currentValue -or $null -eq $expectedValue -or $currentValue -ne $expectedValue) { return New-ParsecResult -Status 'Failed' -Message 'Display scaling mismatch.' -Observed $observed.scaling }
            New-ParsecResult -Status 'Succeeded' -Message 'Display scaling matches.' -Observed $observed.scaling
        }
        reset = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $capturedState = if ($Arguments.ContainsKey('captured_state') -and $Arguments.captured_state -is [System.Collections.IDictionary]) { ConvertTo-ParsecPlainObject -InputObject $Arguments.captured_state } elseif ($null -ne $ExecutionResult -and $ExecutionResult.Outputs.captured_state) { ConvertTo-ParsecPlainObject -InputObject $ExecutionResult.Outputs.captured_state } else { $null }
            if ($null -ne $capturedState -and $capturedState.Contains('text_scale_percent')) { return Invoke-ParsecDisplayAdapter -Method 'SetScaling' -Arguments @{ text_scale_percent = [int] $capturedState.text_scale_percent } }
            if ($null -ne $capturedState -and $capturedState.Contains('ui_scale_percent')) { return Invoke-ParsecDisplayAdapter -Method 'SetScaling' -Arguments @{ ui_scale_percent = [int] $capturedState.ui_scale_percent } }
            New-ParsecResult -Status 'Failed' -Message 'Captured scaling state does not include a resettable text scaling value.' -Errors @('CapabilityUnavailable')
        }
    }
}
