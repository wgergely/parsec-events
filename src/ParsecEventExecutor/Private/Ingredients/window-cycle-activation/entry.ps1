param(
    [Parameter()]
    [System.Collections.IDictionary] $Schema,

    [Parameter()]
    [string] $IngredientPath
)

return @{
    Domain = 'window'
    Operations = @{
        capture = {
            param($ctx, $operationArguments, $prior)

            $capturedState = & $ctx.DomainApi.Invoke 'CaptureState' @{} $null $ctx.StateRoot $ctx.RunState
            New-ParsecResult -Status 'Succeeded' -Message 'Captured window activation state.' -Observed @{
                foreground_window = $capturedState.foreground_window
                window_count = @($capturedState.windows).Count
            } -Outputs @{
                captured_state = @{
                    foreground_window = $capturedState.foreground_window
                }
                windows = @($capturedState.windows)
            }
        }.GetNewClosure()
        apply = {
            param($ctx, $operationArguments, $prior)

            & $ctx.DomainApi.Invoke 'CycleActivation' $operationArguments $prior $ctx.StateRoot $ctx.RunState
        }.GetNewClosure()
        verify = {
            param($ctx, $operationArguments, $prior)

            $capturedState = Get-ParsecCapturedStateFromResult -Arguments $operationArguments -ExecutionResult $prior
            $currentForeground = & $ctx.DomainApi.Invoke 'CaptureState' @{} $prior $ctx.StateRoot $ctx.RunState
            if ($null -eq $capturedState -or -not $capturedState.Contains('foreground_window') -or $null -eq $capturedState.foreground_window) {
                return New-ParsecResult -Status 'Succeeded' -Message 'No original foreground window was captured.' -Observed @{
                    foreground_window = $currentForeground.foreground_window
                } -Outputs @{
                    restored = $false
                }
            }

            $expectedHandle = [int64] $capturedState.foreground_window.handle
            $observedHandle = if ($null -ne $currentForeground.foreground_window -and $currentForeground.foreground_window.handle) { [int64] $currentForeground.foreground_window.handle } else { 0 }
            if ($expectedHandle -ne 0 -and $observedHandle -ne $expectedHandle) {
                return New-ParsecResult -Status 'Failed' -Message 'Foreground window was not restored after activation cycling.' -Observed @{
                    foreground_window = $currentForeground.foreground_window
                } -Outputs @{
                    expected_handle = $expectedHandle
                    observed_handle = $observedHandle
                } -Errors @('ForegroundWindowDrift')
            }

            New-ParsecResult -Status 'Succeeded' -Message 'Foreground window restored after activation cycling.' -Observed @{
                foreground_window = $currentForeground.foreground_window
            } -Outputs @{
                restored = $true
                foreground_window = $currentForeground.foreground_window
            }
        }.GetNewClosure()
        reset = {
            param($ctx, $operationArguments, $prior)

            & $ctx.DomainApi.Invoke 'RestoreForeground' $operationArguments $prior $ctx.StateRoot $ctx.RunState
        }.GetNewClosure()
    }
}
