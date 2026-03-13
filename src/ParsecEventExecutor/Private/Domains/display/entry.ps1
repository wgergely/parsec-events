$domainFile = Join-Path -Path $PSScriptRoot -ChildPath 'Domain.ps1'
. $domainFile

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

            switch ($Method) {
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
                'CapturePrimary' { return Invoke-ParsecDisplayDomainCapturePrimary -Arguments $Arguments -StateRoot $StateRoot }
                'ApplyPrimary' { return Invoke-ParsecDisplayDomainApplyPrimary -Arguments $Arguments -StateRoot $StateRoot }
                'VerifyPrimary' { return Invoke-ParsecDisplayDomainVerifyPrimary -Arguments $Arguments -StateRoot $StateRoot }
                'ResetPrimary' { return Invoke-ParsecDisplayDomainResetPrimary -Arguments $Arguments -ExecutionResult $Prior }
                'CaptureEnabled' { return Invoke-ParsecDisplayDomainCaptureEnabled -Arguments $Arguments -StateRoot $StateRoot }
                'ApplyEnabled' { return Invoke-ParsecDisplayDomainApplyEnabled -Arguments $Arguments -StateRoot $StateRoot }
                'VerifyEnabled' { return Invoke-ParsecDisplayDomainVerifyEnabled -Arguments $Arguments -StateRoot $StateRoot }
                'ResetEnabled' { return Invoke-ParsecDisplayDomainResetEnabled -Arguments $Arguments -ExecutionResult $Prior }
                'CaptureActiveDisplays' { return Invoke-ParsecDisplayDomainCaptureActiveDisplays -Arguments $Arguments -StateRoot $StateRoot }
                'ApplyActiveDisplays' { return Invoke-ParsecDisplayDomainApplyActiveDisplays -Arguments $Arguments -StateRoot $StateRoot }
                'WaitActiveDisplays' { return Invoke-ParsecDisplayDomainWaitActiveDisplays -Arguments $Arguments -StateRoot $StateRoot }
                'VerifyActiveDisplays' { return Invoke-ParsecDisplayDomainVerifyActiveDisplays -Arguments $Arguments -StateRoot $StateRoot }
                'ResetActiveDisplays' { return Invoke-ParsecDisplayDomainResetActiveDisplays -Arguments $Arguments -ExecutionResult $Prior -StateRoot $StateRoot }
                'CaptureScaling' { return Invoke-ParsecDisplayDomainCaptureScaling -Arguments $Arguments -StateRoot $StateRoot }
                'ApplyScaling' { return Invoke-ParsecDisplayDomainApplyScaling -Arguments $Arguments -ExecutionResult $Prior }
                'VerifyScaling' { return Invoke-ParsecDisplayDomainVerifyScaling -Arguments $Arguments -ExecutionResult $Prior }
                'ResetScaling' { return Invoke-ParsecDisplayDomainResetScaling -Arguments $Arguments -ExecutionResult $Prior }
                'CaptureTextScale' { return Invoke-ParsecDisplayDomainCaptureTextScale -Arguments $Arguments }
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
                default { throw "Display domain method '$Method' is not available." }
            }
        }
    }
}
