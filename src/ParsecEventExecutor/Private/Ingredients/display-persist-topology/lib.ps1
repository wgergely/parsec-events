function Get-ParsecIngredientOperations {
    return @{
        capture = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)

            $snapshotName = Resolve-ParsecSnapshotName -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState -UseDefaultCaptureName
            $observed = Get-ParsecObservedState
            $topologyState = Get-ParsecDisplayTopologyCaptureState -ObservedState $observed
            $snapshot = [ordered]@{
                schema_version = 1
                name = $snapshotName
                source = 'capture'
                captured_at = [DateTimeOffset]::UtcNow.ToString('o')
                display = $topologyState
            }
            $path = Save-ParsecSnapshotDocument -Name $snapshotName -SnapshotDocument $snapshot -StateRoot $StateRoot
            $RunState.active_snapshot = $snapshotName
            return New-ParsecResult -Status 'Succeeded' -Message "Captured topology snapshot '$snapshotName'." -Observed $topologyState -Outputs @{
                snapshot_name = $snapshotName
                snapshot = $snapshot
                captured_state = $topologyState
                path = $path
            }
        }
        reset = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)

            $target = Get-ParsecSnapshotTarget -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState
            $RunState.active_snapshot = $target.snapshot_name
            return Invoke-ParsecDisplayTopologyReset -TopologyState $target.snapshot.display -SnapshotName $target.snapshot_name
        }
        verify = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)

            $target = Get-ParsecSnapshotTarget -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState
            $observed = Get-ParsecObservedState
            $verification = Compare-ParsecDisplayTopologyState -TargetState $target.snapshot.display -ObservedState $observed
            $verification.Outputs.snapshot_name = $target.snapshot_name
            return $verification
        }
    }
}
