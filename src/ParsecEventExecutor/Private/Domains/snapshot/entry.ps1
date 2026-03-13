$domainFile = Join-Path -Path $PSScriptRoot -ChildPath 'Snapshot.Domain.ps1'
. $domainFile

return @{
    Name = 'snapshot'
    Api = [pscustomobject]@{
        Invoke = {
            param(
                [string] $Method,
                [System.Collections.IDictionary] $Arguments = @{},
                $Prior,
                [string] $StateRoot = (Get-ParsecDefaultStateRoot),
                [System.Collections.IDictionary] $RunState = @{}
            )

            switch ($Method) {
                'Capture' { return Invoke-ParsecSnapshotDomainCapture -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState }
                'Verify' { return Invoke-ParsecSnapshotDomainVerify -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState }
                'Reset' {
                    if ($null -ne $Prior -and $Prior.Outputs -and $Prior.Outputs.snapshot) {
                        return Invoke-ParsecSnapshotDomainReset -SnapshotDocument $Prior.Outputs.snapshot
                    }

                    $target = Get-ParsecSnapshotDomainTarget -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState
                    return Invoke-ParsecSnapshotDomainReset -SnapshotDocument $target.snapshot
                }
                default { throw "Snapshot domain method '$Method' is not available." }
            }
        }
    }
}
