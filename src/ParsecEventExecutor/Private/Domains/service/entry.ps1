$domainFile = Join-Path -Path $PSScriptRoot -ChildPath 'lib.ps1'
. $domainFile

return @{
    Name = 'service'
    Api = [pscustomobject]@{
        Invoke = {
            param(
                [string] $Method,
                [System.Collections.IDictionary] $Arguments = @{}
            )

            switch ($Method) {
                'Capture' { return Invoke-ParsecServiceDomain -Method 'Capture' -Arguments $Arguments }
                'Start' { return Invoke-ParsecServiceDomain -Method 'Start' -Arguments $Arguments }
                'Stop' { return Invoke-ParsecServiceDomain -Method 'Stop' -Arguments $Arguments }
                'VerifyRunning' { return Invoke-ParsecServiceDomain -Method 'VerifyRunning' -Arguments $Arguments }
                'VerifyStopped' { return Invoke-ParsecServiceDomain -Method 'VerifyStopped' -Arguments $Arguments }
                default { throw "Service domain method '$Method' is not available." }
            }
        }
    }
}
