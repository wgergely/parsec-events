$domainFile = Join-Path -Path $PSScriptRoot -ChildPath 'lib.ps1'
. $domainFile

return @{
    Name = 'process'
    Api = [pscustomobject]@{
        Invoke = {
            param(
                [string] $Method,
                [System.Collections.IDictionary] $Arguments = @{},
                $Prior
            )

            switch ($Method) {
                'Capture' { return Invoke-ParsecProcessDomain -Method 'Capture' -Arguments $Arguments }
                'Start' { return Invoke-ParsecProcessDomain -Method 'Start' -Arguments $Arguments }
                'Stop' { return Invoke-ParsecProcessDomain -Method 'Stop' -Arguments $Arguments -ExecutionResult $Prior }
                'VerifyRunning' { return Invoke-ParsecProcessDomain -Method 'VerifyRunning' -Arguments $Arguments -ExecutionResult $Prior }
                'VerifyStopped' { return Invoke-ParsecProcessDomain -Method 'VerifyStopped' -Arguments $Arguments -ExecutionResult $Prior }
                default { throw "Process domain method '$Method' is not available." }
            }
        }
    }
}
