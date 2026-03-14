$supportFiles = @(
    (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Core\HostSupport.ps1'),
    (Join-Path -Path $PSScriptRoot -ChildPath 'Platform.ps1'),
    (Join-Path -Path $PSScriptRoot -ChildPath 'Personalization.Domain.ps1')
)

return @{
    Name = 'personalization'
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
                'CaptureTheme' { return Get-ParsecThemeCaptureResult }
                'ApplyTheme' { return Invoke-ParsecThemeApply -Arguments $Arguments }
                'VerifyTheme' { return Invoke-ParsecThemeVerify -Arguments $Arguments }
                'ResetTheme' { return Invoke-ParsecThemeReset -Arguments $Arguments -ExecutionResult $Prior }
                'CaptureTextScale' { return Get-ParsecTextScaleCaptureResult }
                'ApplyTextScale' { return Invoke-ParsecTextScaleApply -Arguments $Arguments -ExecutionResult $Prior }
                'WaitTextScale' { return Invoke-ParsecTextScaleWait -Arguments $Arguments -ExecutionResult $Prior }
                'VerifyTextScale' { return Invoke-ParsecTextScaleVerify -Arguments $Arguments -ExecutionResult $Prior }
                'ResetTextScale' { return Invoke-ParsecTextScaleReset -Arguments $Arguments -ExecutionResult $Prior }
                'CaptureUiScale' { return Get-ParsecUiScaleCaptureResult -Arguments $Arguments -StateRoot $StateRoot }
                'ApplyUiScale' { return Invoke-ParsecUiScaleApply -Arguments $Arguments -ExecutionResult $Prior -StateRoot $StateRoot }
                'WaitUiScale' { return Invoke-ParsecUiScaleWait -Arguments $Arguments -ExecutionResult $Prior -StateRoot $StateRoot }
                'VerifyUiScale' { return Invoke-ParsecUiScaleVerify -Arguments $Arguments -ExecutionResult $Prior -StateRoot $StateRoot }
                'ResetUiScale' { return Invoke-ParsecUiScaleReset -Arguments $Arguments -ExecutionResult $Prior }
                default { throw "Personalization domain method '$Method' is not available." }
            }
        }.GetNewClosure()
    }
}
