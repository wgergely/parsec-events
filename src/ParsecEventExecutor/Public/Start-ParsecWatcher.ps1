function Start-ParsecWatcher {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $ConfigPath = (Get-ParsecWatcherDefaultConfigPath),

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [switch] $DryRun
    )

    $config = Read-ParsecWatcherConfig -ConfigPath $ConfigPath
    Write-Information "Watcher: Configuration loaded from '$ConfigPath'"

    if ($DryRun) {
        Write-Information 'Watcher: Running in DRY RUN mode. No recipes will be dispatched.'
    }

    Start-ParsecWatcherLoop -Config $config -StateRoot $StateRoot -DryRun:$DryRun
}

function Stop-ParsecWatcher {
    [CmdletBinding()]
    param()

    Stop-ParsecWatcherLoop
}
