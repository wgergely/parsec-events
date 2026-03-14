$supportFiles = @(
    (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Core\HostSupport.ps1'),
    (Join-Path -Path $PSScriptRoot -ChildPath 'lib.ps1')
)

return @{
    Name = 'sound'
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
                'Capture' { return Invoke-ParsecSoundDomain -Method 'Capture' -Arguments $Arguments }
                'SetPlaybackDevice' { return Invoke-ParsecSoundDomain -Method 'SetPlaybackDevice' -Arguments $Arguments }
                'ResetPlaybackDevice' { return Invoke-ParsecSoundDomain -Method 'ResetPlaybackDevice' -Arguments $Arguments }
                'VerifyPlaybackDevice' { return Invoke-ParsecSoundDomain -Method 'VerifyPlaybackDevice' -Arguments $Arguments }
                'GetPlaybackDevices' { return Invoke-ParsecSoundDomain -Method 'GetPlaybackDevices' -Arguments $Arguments }
                default { throw "Sound domain method '$Method' is not available." }
            }
        }.GetNewClosure()
    }
}
