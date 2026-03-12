function Get-ParsecIngredientOperations {
    return @{
        capture = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $observed = Get-ParsecObservedState
            $textScalePercent = if ($observed.Contains('font_scaling') -and $observed.font_scaling.Contains('text_scale_percent')) {
                [int] $observed.font_scaling.text_scale_percent
            }
            else {
                $null
            }

            New-ParsecResult -Status 'Succeeded' -Message 'Captured text scaling state.' -Observed @{
                text_scale_percent = $textScalePercent
            } -Outputs @{
                captured_state = @{
                    text_scale_percent = $textScalePercent
                }
            }
        }
        apply = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $textScalePercent = if ($Arguments.Contains('text_scale_percent')) {
                [int] $Arguments.text_scale_percent
            }
            elseif ($Arguments.Contains('value')) {
                [int] $Arguments.value
            }
            else {
                $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
                if ($null -ne $capturedState -and $capturedState.Contains('text_scale_percent')) {
                    [int] $capturedState.text_scale_percent
                }
                else {
                    throw 'Text scale operation requires text_scale_percent or value.'
                }
            }
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
        wait = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $expected = if ($Arguments.Contains('text_scale_percent')) {
                [int] $Arguments.text_scale_percent
            }
            elseif ($Arguments.Contains('value')) {
                [int] $Arguments.value
            }
            else {
                $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
                if ($null -ne $capturedState -and $capturedState.Contains('text_scale_percent')) {
                    [int] $capturedState.text_scale_percent
                }
                else {
                    throw 'Text scale operation requires text_scale_percent or value.'
                }
            }
            $observed = Get-ParsecObservedState
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

            New-ParsecResult -Status 'Succeeded' -Message 'Text scale is ready.' -Observed $observed.font_scaling -Outputs @{
                text_scale_percent = $expected
            }
        }
        verify = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $expected = if ($Arguments.Contains('text_scale_percent')) {
                [int] $Arguments.text_scale_percent
            }
            elseif ($Arguments.Contains('value')) {
                [int] $Arguments.value
            }
            else {
                $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
                if ($null -ne $capturedState -and $capturedState.Contains('text_scale_percent')) {
                    [int] $capturedState.text_scale_percent
                }
                else {
                    throw 'Text scale operation requires text_scale_percent or value.'
                }
            }
            $observed = Get-ParsecObservedState
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

            New-ParsecResult -Status 'Succeeded' -Message 'Text scale matches.' -Observed $observed.font_scaling -Outputs @{
                text_scale_percent = $expected
            }
        }
        reset = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
            if ($null -eq $capturedState -or -not $capturedState.Contains('text_scale_percent')) {
                return New-ParsecResult -Status 'Failed' -Message 'Captured text scaling state does not include a resettable value.' -Errors @('MissingCapturedState')
            }

            Invoke-ParsecPersonalizationAdapter -Method 'SetTextScale' -Arguments @{
                text_scale_percent = [int] $capturedState.text_scale_percent
            }
        }
    }
}
