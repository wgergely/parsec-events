function New-ParsecLogTailer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $LogPath,

        [Parameter()]
        [int] $PollIntervalMs = 1000
    )

    if (-not (Test-Path -LiteralPath $LogPath)) {
        throw "Parsec log file not found: '$LogPath'"
    }

    $directory = Split-Path -Path $LogPath -Parent
    $fileName = Split-Path -Path $LogPath -Leaf

    $tailer = [ordered]@{
        log_path = $LogPath
        directory = $directory
        file_name = $fileName
        poll_interval_ms = $PollIntervalMs
        last_position = 0L
        is_running = $false
    }

    return $tailer
}

function Start-ParsecLogTailer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Tailer,

        [Parameter()]
        [switch] $SkipExisting
    )

    if ($Tailer.is_running) {
        throw 'Log tailer is already running.'
    }

    if ($SkipExisting) {
        $fileInfo = Get-Item -LiteralPath $Tailer.log_path -ErrorAction SilentlyContinue
        if ($fileInfo) {
            $Tailer.last_position = $fileInfo.Length
        }
    }
    else {
        $Tailer.last_position = 0L
    }

    $Tailer.is_running = $true
}

function Stop-ParsecLogTailer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Tailer
    )

    $Tailer.is_running = $false
}

function Read-ParsecLogTailerNewLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Tailer
    )

    $logPath = $Tailer.log_path
    if (-not (Test-Path -LiteralPath $logPath)) {
        return @()
    }

    try {
        $stream = [System.IO.FileStream]::new(
            $logPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )

        try {
            $currentSize = $stream.Length

            # Rotation detection: file shrunk since last read
            if ($currentSize -lt $Tailer.last_position) {
                $Tailer.last_position = 0L
            }

            # No new content
            if ($currentSize -le $Tailer.last_position) {
                return @()
            }

            $stream.Seek($Tailer.last_position, [System.IO.SeekOrigin]::Begin) | Out-Null
            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true, 4096, $true)

            try {
                $newLines = [System.Collections.Generic.List[string]]::new()
                while ($null -ne ($line = $reader.ReadLine())) {
                    if ($line.Trim().Length -gt 0) {
                        $newLines.Add($line)
                    }
                }

                $Tailer.last_position = $stream.Position
                return @($newLines)
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }
    }
    catch [System.IO.IOException] {
        Write-Warning "Log file read failed (file may be locked): $_"
        return @()
    }
}

function Read-ParsecLogTailLines {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $LogPath,

        [Parameter()]
        [int] $TailCount = 100
    )

    if (-not (Test-Path -LiteralPath $LogPath)) {
        return @()
    }

    try {
        $stream = [System.IO.FileStream]::new(
            $LogPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )

        try {
            $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)

            try {
                $allLines = [System.Collections.Generic.List[string]]::new()
                while ($null -ne ($line = $reader.ReadLine())) {
                    $allLines.Add($line)
                }

                if ($allLines.Count -le $TailCount) {
                    return @($allLines)
                }

                $startIndex = $allLines.Count - $TailCount
                return @($allLines.GetRange($startIndex, $TailCount))
            }
            finally {
                $reader.Dispose()
            }
        }
        finally {
            $stream.Dispose()
        }
    }
    catch [System.IO.IOException] {
        Write-Warning "Failed to read log tail: $_"
        return @()
    }
}
