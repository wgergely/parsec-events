function Resolve-ParsecSnapshotDomainName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{},

        [Parameter()]
        [switch] $UseDefaultCaptureName
    )

    if ($Arguments.ContainsKey('snapshot_name') -and -not [string]::IsNullOrWhiteSpace($Arguments.snapshot_name)) {
        return [string] $Arguments.snapshot_name
    }

    if ($RunState.ContainsKey('active_snapshot') -and -not [string]::IsNullOrWhiteSpace($RunState.active_snapshot)) {
        return [string] $RunState.active_snapshot
    }

    $executorState = Get-ParsecExecutorStateDocument -StateRoot $StateRoot
    if ($executorState.active_snapshot) {
        return [string] $executorState.active_snapshot
    }

    if ($UseDefaultCaptureName.IsPresent) {
        return 'desktop-pre-parsec'
    }

    throw 'No active snapshot is available.'
}

function Invoke-ParsecSnapshotDomainResolveName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{},

        [Parameter()]
        [bool] $UseDefaultCaptureName = $false
    )

    return Resolve-ParsecSnapshotDomainName -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState -UseDefaultCaptureName:$UseDefaultCaptureName
}

function Get-ParsecSnapshotDomainTarget {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{}
    )

    $snapshotName = Resolve-ParsecSnapshotDomainName -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState
    $snapshot = Read-ParsecSnapshotDocument -Name $snapshotName -StateRoot $StateRoot
    return [ordered]@{
        snapshot_name = $snapshotName
        snapshot = $snapshot
    }
}

function Invoke-ParsecSnapshotDomainCapture {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{}
    )

    $snapshotName = Resolve-ParsecSnapshotDomainName -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState -UseDefaultCaptureName
    $observed = Get-ParsecDisplayDomainObservedState
    $snapshot = [ordered]@{
        schema_version = 1
        name = $snapshotName
        source = 'capture'
        captured_at = [DateTimeOffset]::UtcNow.ToString('o')
        display = $observed
    }
    $path = Save-ParsecSnapshotDocument -Name $snapshotName -SnapshotDocument $snapshot -StateRoot $StateRoot
    $RunState.active_snapshot = $snapshotName
    return New-ParsecResult -Status 'Succeeded' -Message "Captured snapshot '$snapshotName'." -Observed $observed -Outputs @{
        snapshot_name = $snapshotName
        snapshot = $snapshot
        path = $path
    }
}

function Invoke-ParsecSnapshotDomainReset {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $SnapshotDocument
    )

    $topologyResult = Invoke-ParsecDisplayDomainTopologyReset -TopologyState (Get-ParsecDisplayDomainTopologyCaptureState -ObservedState $SnapshotDocument.display) -SnapshotName ([string] $SnapshotDocument.name)
    $actions = New-Object System.Collections.Generic.List[object]
    foreach ($actionResult in @($topologyResult.Outputs.actions)) {
        $actions.Add($actionResult)
    }

    if ($SnapshotDocument.display.Contains('font_scaling') -and $SnapshotDocument.display.font_scaling.Contains('text_scale_percent')) {
        $actions.Add((Invoke-ParsecPersonalizationAdapter -Method 'SetTextScale' -Arguments @{
                    text_scale_percent = [int] $SnapshotDocument.display.font_scaling.text_scale_percent
                }))
    }

    if ($SnapshotDocument.display.Contains('theme')) {
        $actions.Add((Invoke-ParsecPersonalizationAdapter -Method 'SetThemeState' -Arguments @{
                    theme_state = $SnapshotDocument.display.theme
                }))
    }

    if ($SnapshotDocument.display.Contains('wallpaper')) {
        $actions.Add((Invoke-ParsecPersonalizationAdapter -Method 'SetWallpaperState' -Arguments @{
                    wallpaper_state = $SnapshotDocument.display.wallpaper
                }))
    }

    $actionResults = @($actions | ForEach-Object { $_ })
    $failures = @($actionResults | Where-Object { -not (Test-ParsecSuccessfulStatus -Status $_.Status) })
    if ($failures.Count -gt 0) {
        return New-ParsecResult -Status 'Failed' -Message $failures[0].Message -Outputs @{
            snapshot_name = [string] $SnapshotDocument.name
            actions = $actionResults
        } -Errors @('ResetFailed')
    }

    return New-ParsecResult -Status 'Succeeded' -Message "Snapshot '$($SnapshotDocument.name)' restored." -Outputs @{
        snapshot_name = [string] $SnapshotDocument.name
        actions = $actionResults
    }
}

function Invoke-ParsecSnapshotDomainVerify {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{}
    )

    $target = Get-ParsecSnapshotDomainTarget -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState
    $observed = Get-ParsecDisplayDomainObservedState
    $verification = Compare-ParsecDisplayDomainState -TargetState $target.snapshot.display -ObservedState $observed
    $verification.Outputs.snapshot_name = $target.snapshot_name
    return $verification
}
