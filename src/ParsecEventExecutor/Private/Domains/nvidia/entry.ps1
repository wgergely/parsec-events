$supportFiles = @(
    (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Core\HostSupport.ps1'),
    (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'display\Platform.ps1'),
    (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'display\Domain.ps1'),
    (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'NvidiaInterop.ps1'),
    (Join-Path -Path $PSScriptRoot -ChildPath 'Platform.ps1'),
    (Join-Path -Path $PSScriptRoot -ChildPath 'lib.ps1')
)

foreach ($file in @($supportFiles)) {
    . $file
}

return @{
    Name = 'nvidia'
    Api = [pscustomobject]@{
        Invoke = {
            param(
                [string] $Method,
                [System.Collections.IDictionary] $Arguments = @{},
                $Prior,
                [string] $StateRoot = (Get-ParsecDefaultStateRoot),
                [System.Collections.IDictionary] $RunState = @{}
            )

            $module = $ExecutionContext.SessionState.Module
            if ($null -ne $module) {
                return & $module {
                    param($innerFiles, $innerMethod, $innerArguments, $innerStateRoot)
                    foreach ($file in @($innerFiles)) {
                        . $file
                    }

                    switch ($innerMethod) {
                        'ApplyCustomResolution' { return Invoke-ParsecNvidiaDomain -Method 'ApplyCustomResolution' -Arguments $innerArguments -StateRoot $innerStateRoot }
                        'WaitCustomResolution' { return Invoke-ParsecNvidiaDomain -Method 'WaitForCustomResolution' -Arguments $innerArguments -StateRoot $innerStateRoot }
                        'VerifyCustomResolution' { return Invoke-ParsecNvidiaDomain -Method 'VerifyCustomResolution' -Arguments $innerArguments -StateRoot $innerStateRoot }
                        default { throw "NVIDIA domain method '$innerMethod' is not available." }
                    }
                } $supportFiles $Method $Arguments $StateRoot
            }

            switch ($Method) {
                'ApplyCustomResolution' { return Invoke-ParsecNvidiaDomain -Method 'ApplyCustomResolution' -Arguments $Arguments -StateRoot $StateRoot }
                'WaitCustomResolution' { return Invoke-ParsecNvidiaDomain -Method 'WaitForCustomResolution' -Arguments $Arguments -StateRoot $StateRoot }
                'VerifyCustomResolution' { return Invoke-ParsecNvidiaDomain -Method 'VerifyCustomResolution' -Arguments $Arguments -StateRoot $StateRoot }
                default { throw "NVIDIA domain method '$Method' is not available." }
            }
        }.GetNewClosure()
    }
}
