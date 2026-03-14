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

            # Prior, RunState required by domain Invoke contract
            $null = $Prior
            $null = $RunState

            if (-not (Get-Command -Name 'Invoke-ParsecNvidiaDomain' -ErrorAction SilentlyContinue)) {
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
