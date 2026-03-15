function Get-ParsecWatcherDefaultConfigPath {
    [CmdletBinding()]
    param()

    return Join-Path -Path (Get-ParsecRepositoryRoot) -ChildPath 'parsec-watcher.toml'
}

function Read-ParsecWatcherConfig {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $ConfigPath = (Get-ParsecWatcherDefaultConfigPath)
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Watcher configuration file not found: '$ConfigPath'"
    }

    $raw = ConvertFrom-ParsecToml -Path $ConfigPath

    $watcher = [ordered]@{
        parsec_log_path = 'auto'
        apply_delay_ms = 3000
        grace_period_ms = 10000
        poll_interval_ms = 1000
        log_level = 'info'
    }

    if ($raw.Contains('watcher')) {
        $section = $raw.watcher
        foreach ($key in @('parsec_log_path', 'apply_delay_ms', 'grace_period_ms', 'poll_interval_ms', 'log_level')) {
            if ($section.Contains($key)) {
                $watcher[$key] = $section[$key]
            }
        }
    }

    $patterns = [ordered]@{
        connect = '\]\s+(.+#\d+)\s+connected\.\s*$'
        disconnect = '\]\s+(.+#\d+)\s+disconnected\.\s*$'
    }
    # Note: defaults above use literal backslashes. The TOML config file must use
    # double-quoted strings with escaped backslashes because the custom TOML parser
    # does not track single-quoted literal strings for comment stripping, and the
    # '#' in regex patterns would be misinterpreted as a TOML comment.

    if ($raw.Contains('patterns')) {
        $section = $raw.patterns
        foreach ($key in @('connect', 'disconnect')) {
            if ($section.Contains($key)) {
                $patterns[$key] = [string] $section[$key]
            }
        }
    }

    $config = [ordered]@{
        watcher = $watcher
        patterns = $patterns
        path = $ConfigPath
    }

    Test-ParsecWatcherConfigInternal -Config $config

    return $config
}

function Test-ParsecWatcherConfigInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Config
    )

    foreach ($key in @('connect', 'disconnect')) {
        $pattern = $Config.patterns[$key]
        try {
            $null = [regex]::new($pattern)
        }
        catch {
            throw "Watcher config: pattern '$key' is not a valid regex: $pattern"
        }
    }

    $validLogLevels = @('debug', 'info', 'warn', 'error')
    $level = $Config.watcher.log_level
    if ($level -notin $validLogLevels) {
        throw "Watcher config: log_level '$level' is not valid. Must be one of: $($validLogLevels -join ', ')"
    }

    foreach ($key in @('apply_delay_ms', 'grace_period_ms', 'poll_interval_ms')) {
        $value = $Config.watcher[$key]
        if ($value -isnot [int] -and $value -isnot [long]) {
            throw "Watcher config: '$key' must be an integer, got: $value"
        }

        if ($value -lt 0) {
            throw "Watcher config: '$key' must be non-negative, got: $value"
        }
    }
}

function Resolve-ParsecLogPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $ConfiguredPath = 'auto'
    )

    if ($ConfiguredPath -ne 'auto') {
        if (-not (Test-Path -LiteralPath $ConfiguredPath)) {
            throw "Configured Parsec log path does not exist: '$ConfiguredPath'"
        }

        return $ConfiguredPath
    }

    $perMachine = Join-Path -Path ([Environment]::GetFolderPath('CommonApplicationData')) -ChildPath 'Parsec\log.txt'
    if (Test-Path -LiteralPath $perMachine) {
        return $perMachine
    }

    $perUser = Join-Path -Path ([Environment]::GetFolderPath('ApplicationData')) -ChildPath 'Parsec\log.txt'
    if (Test-Path -LiteralPath $perUser) {
        return $perUser
    }

    throw 'Parsec log file not found. Checked per-machine (ProgramData\Parsec\log.txt) and per-user (AppData\Roaming\Parsec\log.txt). Is Parsec installed?'
}
