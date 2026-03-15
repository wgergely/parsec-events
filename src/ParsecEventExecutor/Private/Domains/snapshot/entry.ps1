$supportFiles = @(
    (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Core\HostSupport.ps1'),
    (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'display\Platform.ps1'),
    (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'personalization\Platform.ps1'),
    (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'display\Domain.ps1'),
    (Join-Path -Path $PSScriptRoot -ChildPath 'Snapshot.Domain.ps1')
)

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

            foreach ($file in @($supportFiles)) {
                . $file
            }

            switch ($Method) {
                'ResolveName' { return Invoke-ParsecSnapshotDomainResolveName -Arguments $(if ($Arguments.Contains('arguments')) { [hashtable] $Arguments.arguments } else { @{} }) -StateRoot $StateRoot -RunState $RunState -UseDefaultCaptureName $(if ($Arguments.Contains('use_default_capture_name')) { [bool] $Arguments.use_default_capture_name } else { $false }) }
                'GetTarget' { return Get-ParsecSnapshotDomainTarget -Arguments $(if ($Arguments.Contains('arguments')) { [hashtable] $Arguments.arguments } else { $Arguments }) -StateRoot $StateRoot -RunState $RunState }
                'ResetDocument' { return Invoke-ParsecSnapshotDomainReset -SnapshotDocument ([System.Collections.IDictionary] $Arguments.snapshot_document) }
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
        }.GetNewClosure()
    }
}
