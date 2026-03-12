function Get-ParsecIngredientOperations {
    return @{
        capture = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $observed = Get-ParsecObservedState
            $targetMonitor = Resolve-ParsecDisplayTargetMonitor -ObservedState $observed -Arguments $Arguments
            if ($null -eq $targetMonitor) {
                return New-ParsecResult -Status 'Failed' -Message 'Target monitor could not be resolved.' -Observed $observed -Errors @('MonitorNotFound')
            }

            Get-ParsecDisplayCaptureResult -ObservedState $observed -DeviceName ([string] $targetMonitor.device_name) -Domain 'display ensured resolution'
        }
        apply = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments
            $supportedModes = @(Get-ParsecSupportedDisplayModes -DeviceName $deviceName)
            $requestedWidth = [int] $Arguments.width
            $requestedHeight = [int] $Arguments.height
            $requestedOrientation = if ($Arguments.ContainsKey('orientation')) { [string] $Arguments.orientation } else { $null }
            $matchingMode = @($supportedModes | Where-Object {
                $_.width -eq $requestedWidth -and
                $_.height -eq $requestedHeight -and
                ($null -eq $requestedOrientation -or $_.orientation -eq $requestedOrientation)
            } | Select-Object -First 1)

            $resolutionArguments = @{
                device_name = $deviceName
                width       = $requestedWidth
                height      = $requestedHeight
            }

            $resolutionResult = Invoke-ParsecDisplayAdapter -Method 'SetResolution' -Arguments $resolutionArguments
            if (-not (Test-ParsecSuccessfulStatus -Status $resolutionResult.Status)) {
                return $resolutionResult
            }

            if ($requestedOrientation) {
                $orientationResult = Invoke-ParsecDisplayAdapter -Method 'SetOrientation' -Arguments @{
                    device_name = $deviceName
                    orientation = $requestedOrientation
                }

                if (-not (Test-ParsecSuccessfulStatus -Status $orientationResult.Status)) {
                    return $orientationResult
                }
            }

            New-ParsecResult -Status 'Succeeded' -Message "Ensured resolution ${requestedWidth}x${requestedHeight} on '$deviceName'." -Requested $Arguments -Outputs @{
                device_name             = $deviceName
                width                   = $requestedWidth
                height                  = $requestedHeight
                orientation             = $requestedOrientation
                mode_preexisting        = ($matchingMode.Count -gt 0)
                supported_mode_count    = @($supportedModes).Count
                supported_modes_sample  = @($supportedModes | Select-Object -First 10)
            }
        }
        verify = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments
            $observed = Get-ParsecObservedState
            $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $deviceName
            if ($null -eq $monitor) {
                return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' not found." -Observed $observed
            }

            if ($monitor.bounds.width -ne [int] $Arguments.width -or $monitor.bounds.height -ne [int] $Arguments.height) {
                return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' resolution mismatch." -Observed $monitor
            }

            if ($Arguments.ContainsKey('orientation') -and $monitor.orientation -ne [string] $Arguments.orientation) {
                return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' orientation mismatch." -Observed $monitor
            }

            New-ParsecResult -Status 'Succeeded' -Message 'Ensured resolution matches.' -Observed $monitor
        }
        reset = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $capturedMonitor = Get-ParsecDisplayResetMonitorState -Arguments $Arguments -ExecutionResult $ExecutionResult
            if ($null -eq $capturedMonitor -or -not $capturedMonitor.Contains('bounds')) {
                return New-ParsecResult -Status 'Failed' -Message 'Captured ensured-resolution state does not include a resettable value.' -Errors @('MissingCapturedState')
            }

            Invoke-ParsecIngredientOperation -Name 'display.set-resolution' -Operation 'reset' -Arguments @{ captured_state = $capturedMonitor } -RunState $RunState
        }
    }
}
