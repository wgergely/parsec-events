param(
    [Parameter()]
    [System.Collections.IDictionary] $Schema,

    [Parameter()]
    [string] $IngredientPath
)

. (Join-Path -Path $PSScriptRoot -ChildPath 'private.ps1')

return @{
    Domain = 'window'
    Operations = @{
        capture = {
            param($ctx, $operationArguments, $prior)
            $state = Get-ParsecWindowCaptureState
            New-ParsecResult -Status 'Succeeded' -Message 'Captured window activation state.' -Observed @{
                foreground_window = $state.foreground_window
                window_count = @($state.windows).Count
            } -Outputs @{
                captured_state = @{
                    foreground_window = $state.foreground_window
                }
                windows = @($state.windows)
            }
        }
        apply = {
            param($ctx, $operationArguments, $prior)
            Invoke-ParsecWindowCycleInternal -Arguments $operationArguments
        }
        verify = {
            param($ctx, $operationArguments, $prior)
            $capturedState = Get-ParsecCapturedStateFromResult -Arguments $operationArguments -ExecutionResult $prior
            $currentForeground = Invoke-ParsecWindowAdapter -Method 'GetForegroundWindowInfo'
            if ($null -eq $capturedState -or -not $capturedState.Contains('foreground_window') -or $null -eq $capturedState.foreground_window) {
                return New-ParsecResult -Status 'Succeeded' -Message 'No original foreground window was captured.' -Observed @{
                    foreground_window = $currentForeground
                } -Outputs @{
                    restored = $false
                }
            }

            $expectedHandle = [int64] $capturedState.foreground_window.handle
            $observedHandle = if ($null -ne $currentForeground -and $currentForeground.handle) { [int64] $currentForeground.handle } else { 0 }
            if ($expectedHandle -ne 0 -and $observedHandle -ne $expectedHandle) {
                return New-ParsecResult -Status 'Failed' -Message 'Foreground window was not restored after activation cycling.' -Observed @{
                    foreground_window = $currentForeground
                } -Outputs @{
                    expected_handle = $expectedHandle
                    observed_handle = $observedHandle
                } -Errors @('ForegroundWindowDrift')
            }

            New-ParsecResult -Status 'Succeeded' -Message 'Foreground window restored after activation cycling.' -Observed @{
                foreground_window = $currentForeground
            } -Outputs @{
                restored = $true
                foreground_window = $currentForeground
            }
        }
        reset = {
            param($ctx, $operationArguments, $prior)
            Restore-ParsecWindowForegroundInternal -Arguments $operationArguments -ExecutionResult $prior
        }
    }
}

