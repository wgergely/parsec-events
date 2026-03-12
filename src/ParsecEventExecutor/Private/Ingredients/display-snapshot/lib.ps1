function Get-ParsecIngredientOperations {
    return @{
        capture = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $snapshotName = Resolve-ParsecSnapshotName -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState -UseDefaultCaptureName
            $observed = Get-ParsecObservedState
            $snapshot = [ordered]@{ schema_version = 1; name = $snapshotName; source = 'capture'; captured_at = [DateTimeOffset]::UtcNow.ToString('o'); display = $observed }
            $path = Save-ParsecSnapshotDocument -Name $snapshotName -SnapshotDocument $snapshot -StateRoot $StateRoot
            $RunState.active_snapshot = $snapshotName
            return New-ParsecResult -Status 'Succeeded' -Message "Captured snapshot '$snapshotName'." -Observed $observed -Outputs @{ snapshot_name = $snapshotName; snapshot = $snapshot; path = $path }
        }
        reset = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $target = Get-ParsecSnapshotTarget -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState
            $RunState.active_snapshot = $target.snapshot_name
            return Invoke-ParsecSnapshotReset -SnapshotDocument $target.snapshot
        }
        verify = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $target = Get-ParsecSnapshotTarget -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState
            $observed = Get-ParsecObservedState
            $verification = Compare-ParsecDisplayState -TargetState $target.snapshot.display -ObservedState $observed
            $verification.Outputs.snapshot_name = $target.snapshot_name
            return $verification
        }
    }
}