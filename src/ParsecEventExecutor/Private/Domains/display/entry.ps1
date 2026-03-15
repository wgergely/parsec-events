$supportFiles = @(
    (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Core\HostSupport.ps1'),
    (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'personalization\Platform.ps1'),
    (Join-Path -Path $PSScriptRoot -ChildPath 'Platform.ps1'),
    (Join-Path -Path $PSScriptRoot -ChildPath 'Domain.ps1'),
    (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'snapshot\Snapshot.Domain.ps1')
)

return @{
    Name = 'display'
    Api = [pscustomobject]@{
        Invoke = {
            param(
                [string] $Method,
                [System.Collections.IDictionary] $Arguments = @{},
                $Prior,
                [string] $StateRoot = (Get-ParsecDefaultStateRoot),
                [System.Collections.IDictionary] $RunState = @{}
            )

            $module = Get-Module -Name 'ParsecEventExecutor'
            if ($null -ne $module) {
                & $module {
                    param($files)
                    foreach ($file in @($files)) {
                        . $file
                    }
                } $supportFiles
            }

            foreach ($file in @($supportFiles)) {
                . $file
            }

            switch ($Method) {
                'GetInventory' { return Get-ParsecDisplayDomainInventory -StateRoot $StateRoot }
                'GetAuditState' { return Get-ParsecDisplayDomainAuditState -StateRoot $StateRoot }
                'CaptureMonitorState' { return Invoke-ParsecDisplayDomainCaptureMonitorState -Domain ([string] $Arguments.domain) -Arguments $Arguments -StateRoot $StateRoot }
                'ApplyResolution' { return Invoke-ParsecDisplayDomainApplyResolution -Arguments $Arguments -StateRoot $StateRoot }
                'WaitResolution' { return Invoke-ParsecDisplayDomainWaitResolution -Arguments $Arguments -StateRoot $StateRoot }
                'VerifyResolution' { return Invoke-ParsecDisplayDomainVerifyResolution -Arguments $Arguments -StateRoot $StateRoot }
                'ResetResolution' { return Invoke-ParsecDisplayDomainResetResolution -Arguments $Arguments -ExecutionResult $Prior }
                'ApplyEnsureResolution' { return Invoke-ParsecDisplayDomainApplyEnsureResolution -Arguments $Arguments -ExecutionResult $Prior -StateRoot $StateRoot -RunState $RunState }
                'VerifyEnsureResolution' { return Invoke-ParsecDisplayDomainVerifyEnsureResolution -Arguments $Arguments -StateRoot $StateRoot }
                'ResetEnsureResolution' { return Invoke-ParsecDisplayDomainResetEnsureResolution -Arguments $Arguments -ExecutionResult $Prior }
                'ApplyOrientation' { return Invoke-ParsecDisplayDomainApplyOrientation -Arguments $Arguments -StateRoot $StateRoot }
                'WaitOrientation' { return Invoke-ParsecDisplayDomainWaitOrientation -Arguments $Arguments -StateRoot $StateRoot }
                'VerifyOrientation' { return Invoke-ParsecDisplayDomainVerifyOrientation -Arguments $Arguments -StateRoot $StateRoot }
                'ResetOrientation' { return Invoke-ParsecDisplayDomainResetOrientation -Arguments $Arguments -ExecutionResult $Prior }
                'CapturePrimary' { return Invoke-ParsecDisplayDomainCapturePrimary -Arguments $Arguments }
                'ApplyPrimary' { return Invoke-ParsecDisplayDomainApplyPrimary -Arguments $Arguments }
                'VerifyPrimary' { return Invoke-ParsecDisplayDomainVerifyPrimary -Arguments $Arguments }
                'ResetPrimary' { return Invoke-ParsecDisplayDomainResetPrimary -Arguments $Arguments -ExecutionResult $Prior }
                'CaptureEnabled' { return Invoke-ParsecDisplayDomainCaptureEnabled -Arguments $Arguments }
                'ApplyEnabled' { return Invoke-ParsecDisplayDomainApplyEnabled -Arguments $Arguments }
                'VerifyEnabled' { return Invoke-ParsecDisplayDomainVerifyEnabled -Arguments $Arguments }
                'ResetEnabled' { return Invoke-ParsecDisplayDomainResetEnabled -Arguments $Arguments -ExecutionResult $Prior }
                'CaptureActiveDisplay' { return Invoke-ParsecDisplayDomainCaptureActiveDisplay }
                'ApplyActiveDisplay' { return Invoke-ParsecDisplayDomainApplyActiveDisplay -Arguments $Arguments -StateRoot $StateRoot }
                'WaitActiveDisplay' { return Invoke-ParsecDisplayDomainWaitActiveDisplay -Arguments $Arguments -ExecutionResult $Prior -StateRoot $StateRoot }
                'VerifyActiveDisplay' { return Invoke-ParsecDisplayDomainVerifyActiveDisplay -Arguments $Arguments -ExecutionResult $Prior -StateRoot $StateRoot }
                'ResetActiveDisplay' { return Invoke-ParsecDisplayDomainResetActiveDisplay -Arguments $Arguments -ExecutionResult $Prior }
                'CaptureScaling' { return Invoke-ParsecDisplayDomainCaptureScaling -Arguments $Arguments }
                'ApplyScaling' { return Invoke-ParsecDisplayDomainApplyScaling -Arguments $Arguments }
                'VerifyScaling' { return Invoke-ParsecDisplayDomainVerifyScaling -Arguments $Arguments }
                'ResetScaling' { return Invoke-ParsecDisplayDomainResetScaling -Arguments $Arguments -ExecutionResult $Prior }
                'CaptureTextScale' { return Invoke-ParsecDisplayDomainCaptureTextScale }
                'ApplyTextScale' { return Invoke-ParsecDisplayDomainApplyTextScale -Arguments $Arguments -ExecutionResult $Prior }
                'WaitTextScale' { return Invoke-ParsecDisplayDomainWaitTextScale -Arguments $Arguments -ExecutionResult $Prior }
                'VerifyTextScale' { return Invoke-ParsecDisplayDomainVerifyTextScale -Arguments $Arguments -ExecutionResult $Prior }
                'ResetTextScale' { return Invoke-ParsecDisplayDomainResetTextScale -Arguments $Arguments -ExecutionResult $Prior }
                'CaptureUiScale' { return Invoke-ParsecDisplayDomainCaptureUiScale -Arguments $Arguments -StateRoot $StateRoot }
                'ApplyUiScale' { return Invoke-ParsecDisplayDomainApplyUiScale -Arguments $Arguments -ExecutionResult $Prior -StateRoot $StateRoot }
                'WaitUiScale' { return Invoke-ParsecDisplayDomainWaitUiScale -Arguments $Arguments -ExecutionResult $Prior -StateRoot $StateRoot }
                'VerifyUiScale' { return Invoke-ParsecDisplayDomainVerifyUiScale -Arguments $Arguments -ExecutionResult $Prior -StateRoot $StateRoot }
                'ResetUiScale' { return Invoke-ParsecDisplayDomainResetUiScale -Arguments $Arguments -ExecutionResult $Prior }
                'CaptureSnapshot' { return Invoke-ParsecDisplayDomainCaptureSnapshot -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState }
                'ResetSnapshot' { return Invoke-ParsecDisplayDomainResetSnapshot -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState }
                'VerifySnapshot' { return Invoke-ParsecDisplayDomainVerifySnapshot -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState }
                'CaptureTopologySnapshot' { return Invoke-ParsecDisplayDomainCaptureTopologySnapshot -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState }
                'ResetTopologySnapshot' { return Invoke-ParsecDisplayDomainResetTopologySnapshot -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState }
                'VerifyTopologySnapshot' { return Invoke-ParsecDisplayDomainVerifyTopologySnapshot -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState }
                'CaptureTopologyState' { return Get-ParsecDisplayDomainTopologyCaptureState -ObservedState $(if ($Arguments.Contains('observed_state')) { [System.Collections.IDictionary] $Arguments.observed_state } else { Get-ParsecDisplayDomainObservedState }) }
                'ResetTopologyState' { return Invoke-ParsecDisplayDomainTopologyReset -TopologyState ([System.Collections.IDictionary] $Arguments.topology_state) -SnapshotName $(if ($Arguments.Contains('snapshot_name')) { [string] $Arguments.snapshot_name } else { '' }) }
                'CompareTopologyState' { return Compare-ParsecDisplayDomainTopologyState -TargetState ([hashtable] $Arguments.target_state) -ObservedState ([hashtable] $Arguments.observed_state) }
                'CompareState' { return Compare-ParsecDisplayDomainState -TargetState ([hashtable] $Arguments.target_state) -ObservedState ([hashtable] $Arguments.observed_state) }
                default { throw "Display domain method '$Method' is not available." }
            }
        }.GetNewClosure()
    }
}
