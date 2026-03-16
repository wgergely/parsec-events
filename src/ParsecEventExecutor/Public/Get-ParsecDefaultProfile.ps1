function Get-ParsecDefaultProfile {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $executorState = Get-ParsecExecutorStateDocument -StateRoot $StateRoot
    if (-not $executorState.default_profile) {
        return $null
    }

    $snapshotPath = Get-ParsecSnapshotDocumentPath -Name $executorState.default_profile -StateRoot $StateRoot
    if (-not (Test-Path -LiteralPath $snapshotPath)) {
        return $null
    }

    return Read-ParsecSnapshotDocument -Name $executorState.default_profile -StateRoot $StateRoot
}
