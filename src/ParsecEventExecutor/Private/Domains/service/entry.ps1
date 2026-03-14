$supportFiles = @(
    (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Core\HostSupport.ps1'),
    (Join-Path -Path $PSScriptRoot -ChildPath 'lib.ps1')
)

return @{
    Name = 'service'
    Api = [pscustomobject]@{
        Invoke = {
            param(
                [string] $Method,
                [System.Collections.IDictionary] $Arguments = @{},
                $Prior,
                [string] $StateRoot = (Get-ParsecDefaultStateRoot),
                [System.Collections.IDictionary] $RunState = @{}
            )

            # Prior, StateRoot, RunState required by domain Invoke contract
            $null = $Prior
            $null = $StateRoot
            $null = $RunState

            foreach ($file in @($supportFiles)) {
                . $file
            }

            switch ($Method) {
                'Capture' { return Invoke-ParsecServiceDomain -Method 'Capture' -Arguments $Arguments }
                'Start' { return Invoke-ParsecServiceDomain -Method 'Start' -Arguments $Arguments }
                'Stop' { return Invoke-ParsecServiceDomain -Method 'Stop' -Arguments $Arguments }
                'VerifyRunning' { return Invoke-ParsecServiceDomain -Method 'VerifyRunning' -Arguments $Arguments }
                'ResetStopped' { return Invoke-ParsecServiceDomain -Method 'ResetStopped' -Arguments $Arguments }
                'VerifyStopped' { return Invoke-ParsecServiceDomain -Method 'VerifyStopped' -Arguments $Arguments }
                default { throw "Service domain method '$Method' is not available." }
            }
        }.GetNewClosure()
    }
}
