$supportFiles = @(
    (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Core\HostSupport.ps1'),
    (Join-Path -Path $PSScriptRoot -ChildPath 'lib.ps1')
)

return @{
    Name = 'process'
    Api = [pscustomobject]@{
        Invoke = {
            param(
                [string] $Method,
                [System.Collections.IDictionary] $Arguments = @{},
                $Prior,
                [string] $StateRoot = (Get-ParsecDefaultStateRoot),
                [System.Collections.IDictionary] $RunState = @{}
            )

            # StateRoot, RunState required by domain Invoke contract
            $null = $StateRoot
            $null = $RunState

            foreach ($file in @($supportFiles)) {
                . $file
            }

            switch ($Method) {
                'Capture' { return Invoke-ParsecProcessDomain -Method 'Capture' -Arguments $Arguments -Prior $Prior }
                'Start' { return Invoke-ParsecProcessDomain -Method 'Start' -Arguments $Arguments -Prior $Prior }
                'Stop' { return Invoke-ParsecProcessDomain -Method 'Stop' -Arguments $Arguments -Prior $Prior }
                'ResetStopped' { return Invoke-ParsecProcessDomain -Method 'ResetStopped' -Arguments $Arguments -Prior $Prior }
                'Restart' { return Invoke-ParsecProcessDomain -Method 'Restart' -Arguments $Arguments -Prior $Prior }
                'ResetRestarted' { return Invoke-ParsecProcessDomain -Method 'ResetRestarted' -Arguments $Arguments -Prior $Prior }
                'VerifyRunning' { return Invoke-ParsecProcessDomain -Method 'VerifyRunning' -Arguments $Arguments -Prior $Prior }
                'VerifyStopped' { return Invoke-ParsecProcessDomain -Method 'VerifyStopped' -Arguments $Arguments -Prior $Prior }
                default { throw "Process domain method '$Method' is not available." }
            }
        }.GetNewClosure()
    }
}
