$domainFile = Join-Path -Path $PSScriptRoot -ChildPath 'lib.ps1'
. $domainFile

return @{
    Name = 'nvidia'
    Api = [pscustomobject]@{
        Invoke = {
            param(
                [string] $Method,
                [System.Collections.IDictionary] $Arguments = @{},
                $Prior,
                [string] $StateRoot = (Get-ParsecDefaultStateRoot)
            )

            switch ($Method) {
                'ApplyCustomResolution' { return Invoke-ParsecNvidiaDomain -Method 'ApplyCustomResolution' -Arguments $Arguments -StateRoot $StateRoot }
                'WaitCustomResolution' { return Invoke-ParsecNvidiaDomain -Method 'WaitForCustomResolution' -Arguments $Arguments -StateRoot $StateRoot }
                'VerifyCustomResolution' { return Invoke-ParsecNvidiaDomain -Method 'VerifyCustomResolution' -Arguments $Arguments -StateRoot $StateRoot }
                default { throw "NVIDIA domain method '$Method' is not available." }
            }
        }
    }
}
