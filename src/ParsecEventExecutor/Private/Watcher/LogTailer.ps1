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
        last_size = 0L
        watcher = $null
        debounce_timer = $null
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
            $Tailer.last_size = $fileInfo.Length
        }
    }
    else {
        $Tailer.last_position = 0L
        $Tailer.last_size = 0L
    }

    # Set script-scope variables BEFORE registering events to prevent race condition
    $script:ParsecLogTailerPath = $Tailer.log_path
    $script:ParsecLogTailerPosition = $Tailer.last_position

    # Clean up any orphaned registrations from a prior unclean shutdown
    foreach ($sourceId in @('Parsec.LogFile.Changed', 'Parsec.LogFile.Created', 'Parsec.LogFile.Error', 'Parsec.LogFile.ReadRequest')) {
        Unregister-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue
        Remove-Job -Name $sourceId -ErrorAction SilentlyContinue
    }

    $watcher = [System.IO.FileSystemWatcher]::new($Tailer.directory, $Tailer.file_name)
    $watcher.NotifyFilter = [System.IO.NotifyFilters]::LastWrite -bor [System.IO.NotifyFilters]::Size -bor [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::CreationTime
    $watcher.EnableRaisingEvents = $true

    $Tailer.watcher = $watcher

    Register-ObjectEvent -InputObject $watcher -EventName Changed -SourceIdentifier 'Parsec.LogFile.Changed' -Action {
        New-Event -SourceIdentifier 'Parsec.LogFile.ReadRequest' -MessageData @{ Reason = 'Changed' }
    } | Out-Null

    Register-ObjectEvent -InputObject $watcher -EventName Created -SourceIdentifier 'Parsec.LogFile.Created' -Action {
        New-Event -SourceIdentifier 'Parsec.LogFile.ReadRequest' -MessageData @{ Reason = 'Rotated' }
    } | Out-Null

    Register-ObjectEvent -InputObject $watcher -EventName Error -SourceIdentifier 'Parsec.LogFile.Error' -Action {
        New-Event -SourceIdentifier 'Parsec.LogFile.ReadRequest' -MessageData @{ Reason = 'Error'; Error = $EventArgs }
    } | Out-Null

    Register-EngineEvent -SourceIdentifier 'Parsec.LogFile.ReadRequest' -Action {
        $reason = $Event.MessageData.Reason

        if ($reason -eq 'Rotated') {
            $script:ParsecLogTailerPosition = 0L
        }

        if ($reason -eq 'Error') {
            Write-Warning "FileSystemWatcher error: $($Event.MessageData.Error)"
            return
        }

        $logPath = $script:ParsecLogTailerPath
        if (-not $logPath -or -not (Test-Path -LiteralPath $logPath)) {
            return
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

                if ($currentSize -lt $script:ParsecLogTailerPosition) {
                    $script:ParsecLogTailerPosition = 0L
                }

                if ($currentSize -le $script:ParsecLogTailerPosition) {
                    return
                }

                $stream.Seek($script:ParsecLogTailerPosition, [System.IO.SeekOrigin]::Begin) | Out-Null
                $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true, 4096, $true)

                try {
                    while ($null -ne ($line = $reader.ReadLine())) {
                        if ($line.Trim().Length -gt 0) {
                            New-Event -SourceIdentifier 'Parsec.LogLine' -MessageData @{
                                Line = $line
                                Timestamp = [DateTimeOffset]::UtcNow.ToString('o')
                            }
                        }
                    }

                    $script:ParsecLogTailerPosition = $stream.Position
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
        }
    } | Out-Null

    $Tailer.is_running = $true
}

function Stop-ParsecLogTailer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Tailer
    )

    foreach ($sourceId in @(
            'Parsec.LogFile.Changed',
            'Parsec.LogFile.Created',
            'Parsec.LogFile.Error',
            'Parsec.LogFile.ReadRequest'
        )) {
        Unregister-Event -SourceIdentifier $sourceId -ErrorAction SilentlyContinue
        Remove-Job -Name $sourceId -ErrorAction SilentlyContinue
    }

    if ($Tailer.watcher) {
        $Tailer.watcher.EnableRaisingEvents = $false
        $Tailer.watcher.Dispose()
        $Tailer.watcher = $null
    }

    $Tailer.is_running = $false
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
