function Get-ParsecIngredientOperations {
    return @{
        capture = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $observed = Get-ParsecObservedState
            $capturedState = Get-ParsecDisplayTopologyCaptureState -ObservedState $observed
            New-ParsecResult -Status 'Succeeded' -Message 'Captured active display topology.' -Observed $observed -Outputs @{
                captured_state = $capturedState
            }
        }
        apply = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $observed = Get-ParsecObservedState
            $resolution = Resolve-ParsecActiveDisplayTargetState -ObservedState $observed -Arguments $Arguments -StateRoot $StateRoot
            if (-not (Test-ParsecSuccessfulStatus -Status $resolution.Status)) {
                return $resolution
            }

            $targetState = ConvertTo-ParsecPlainObject -InputObject $resolution.Outputs.target_state
            $result = Invoke-ParsecDisplayTopologyReset -TopologyState $targetState -SnapshotName 'set-activedisplays'
            $result.Requested = [ordered]@{
                screen_ids = @($resolution.Outputs.requested_screen_ids)
            }
            $result.Outputs = [ordered]@{
                target_state = $targetState
                requested_screen_ids = @($resolution.Outputs.requested_screen_ids)
                requested_device_names = @($resolution.Outputs.requested_device_names)
                primary_device_name = [string] $resolution.Outputs.primary_device_name
                topology_restore = if ($result.Outputs.Contains('actions')) {
                    [ordered]@{
                        snapshot_name = [string] $result.Outputs.snapshot_name
                        actions = @($result.Outputs.actions)
                    }
                }
                else {
                    $null
                }
            }
            if (Test-ParsecSuccessfulStatus -Status $result.Status) {
                $result.Message = 'Applied active display topology.'
            }

            return $result
        }
        wait = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $targetState = Resolve-ParsecActiveDisplayTargetStateForOperation -ExecutionResult $ExecutionResult -Arguments $Arguments -StateRoot $StateRoot
            if ($targetState -isnot [System.Collections.IDictionary]) {
                return $targetState
            }

            $observed = Get-ParsecObservedState
            $comparison = Compare-ParsecActiveDisplaySelectionState -TargetState $targetState -ObservedState $observed
            if (-not (Test-ParsecSuccessfulStatus -Status $comparison.Status)) {
                return New-ParsecResult -Status 'Failed' -Message 'Display topology is still settling.' -Observed $observed -Outputs @{
                    mismatches = if ($comparison.Outputs.Contains('mismatches')) { @($comparison.Outputs.mismatches) } else { @() }
                    target_state = $targetState
                } -Errors @('ReadinessPending')
            }

            New-ParsecResult -Status 'Succeeded' -Message 'Display topology is ready.' -Observed $observed -Outputs @{
                target_state = $targetState
            }
        }
        verify = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $targetState = Resolve-ParsecActiveDisplayTargetStateForOperation -ExecutionResult $ExecutionResult -Arguments $Arguments -StateRoot $StateRoot
            if ($targetState -isnot [System.Collections.IDictionary]) {
                return $targetState
            }

            $observed = Get-ParsecObservedState
            $comparison = Compare-ParsecActiveDisplaySelectionState -TargetState $targetState -ObservedState $observed
            if (-not (Test-ParsecSuccessfulStatus -Status $comparison.Status)) {
                return New-ParsecResult -Status 'Failed' -Message 'Observed display topology does not match the requested active-display set.' -Observed $observed -Outputs @{
                    mismatches = if ($comparison.Outputs.Contains('mismatches')) { @($comparison.Outputs.mismatches) } else { @() }
                    target_state = $targetState
                } -Errors @('ActiveDisplayDrift')
            }

            New-ParsecResult -Status 'Succeeded' -Message 'Observed display topology matches the requested active-display set.' -Observed $observed -Outputs @{
                target_state = $targetState
            }
        }
        reset = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
            if ($null -eq $capturedState) {
                return New-ParsecResult -Status 'Failed' -Message 'Captured topology state does not include a resettable value.' -Errors @('MissingCapturedState')
            }

            Invoke-ParsecDisplayTopologyReset -TopologyState $capturedState -SnapshotName 'set-activedisplays-reset'
        }
    }
}
