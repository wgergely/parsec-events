param(
    [Parameter()]
    [System.Collections.IDictionary] $Schema,

    [Parameter()]
    [string] $IngredientPath
)

# Schema, IngredientPath required by ingredient entry contract
$null = $Schema
$null = $IngredientPath

return @{
    Domain = 'window'
    Operations = @{
        capture = {
            param($ctx, $operationArguments, $prior)

            # operationArguments, prior required by ingredient operation contract
            $null = $operationArguments
            $null = $prior

            $capturedState = & $ctx.DomainApi.Invoke 'CaptureState' @{} $null $ctx.StateRoot $ctx.RunState
            & $ctx.Results.Succeed 'Captured window activation state.' @{
                foreground_window = $capturedState.foreground_window
                window_count = @($capturedState.windows).Count
            } @{
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

            $capturedState = if ($operationArguments.Contains('captured_state') -and $operationArguments.captured_state -is [System.Collections.IDictionary]) {
                $operationArguments.captured_state
            }
            elseif ($null -ne $prior -and $prior.Outputs -and $prior.Outputs.captured_state) {
                $prior.Outputs.captured_state
            }
            else {
                $null
            }
            $currentForeground = & $ctx.DomainApi.Invoke 'CaptureState' @{} $prior $ctx.StateRoot $ctx.RunState
            if ($null -eq $capturedState -or -not $capturedState.Contains('foreground_window') -or $null -eq $capturedState.foreground_window) {
                return & $ctx.Results.Succeed 'No original foreground window was captured.' @{
                    foreground_window = $currentForeground.foreground_window
                } @{
                    restored = $false
                }
            }

            $expectedHandle = [int64] $capturedState.foreground_window.handle
            $observedHandle = if ($null -ne $currentForeground.foreground_window -and $currentForeground.foreground_window.handle) { [int64] $currentForeground.foreground_window.handle } else { 0 }
            if ($expectedHandle -ne 0 -and $observedHandle -ne $expectedHandle) {
                return & $ctx.Results.Fail 'Foreground window was not restored after activation cycling.' @{
                    foreground_window = $currentForeground.foreground_window
                } @{
                    expected_handle = $expectedHandle
                    observed_handle = $observedHandle
                } @('ForegroundWindowDrift')
            }

            & $ctx.Results.Succeed 'Foreground window restored after activation cycling.' @{
                foreground_window = $currentForeground.foreground_window
            } @{
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
