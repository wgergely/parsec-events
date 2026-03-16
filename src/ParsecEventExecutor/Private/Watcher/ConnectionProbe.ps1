function Test-ParsecProcessRunning {
    [CmdletBinding()]
    param()

    $procs = Get-Process -Name 'parsecd' -ErrorAction SilentlyContinue
    return ($null -ne $procs -and @($procs).Count -gt 0)
}

function Test-ParsecActiveStream {
    [CmdletBinding()]
    param()

    $procs = Get-Process -Name 'parsecd' -ErrorAction SilentlyContinue
    if (-not $procs) {
        return $false
    }

    foreach ($proc in @($procs)) {
        $endpoints = Get-NetUDPEndpoint -OwningProcess $proc.Id -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalAddress -ne '127.0.0.1' -and $_.LocalAddress -ne '::1' }

        if ($endpoints) {
            return $true
        }
    }

    return $false
}

function Get-ParsecLastSystemBoot {
    [CmdletBinding()]
    param()

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        return [DateTimeOffset]::new($os.LastBootUpTime)
    }
    catch {
        Write-Warning "ConnectionProbe: Could not determine last boot time: $_"
        return $null
    }
}

function Test-ParsecConnectionStale {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $LogLine,

        [Parameter()]
        [int] $MaxAgeHours = 72
    )

    # Extract timestamp from log line format: [I 2026-03-15 00:02:58]
    if ($LogLine -match '^\[.\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\]') {
        $eventTime = [DateTimeOffset]::ParseExact(
            $Matches[1],
            'yyyy-MM-dd HH:mm:ss',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeLocal
        )

        $age = [DateTimeOffset]::Now - $eventTime
        return $age.TotalHours -gt $MaxAgeHours
    }

    # If we can't parse the timestamp, treat as stale
    return $true
}

function Test-ParsecSystemRebootedSince {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $LogLine
    )

    if ($LogLine -match '^\[.\s+(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\]') {
        $eventTime = [DateTimeOffset]::ParseExact(
            $Matches[1],
            'yyyy-MM-dd HH:mm:ss',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AssumeLocal
        )

        $lastBoot = Get-ParsecLastSystemBoot
        if ($null -eq $lastBoot) {
            return $false
        }

        return $lastBoot -gt $eventTime
    }

    return $false
}

function Invoke-ParsecConnectionProbe {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $LastConnectLine = $null,

        [Parameter()]
        [int] $MaxAgeHours = 72
    )

    $result = [ordered]@{
        parsec_running = $false
        active_stream = $false
        connection_stale = $false
        system_rebooted = $false
        verdict = 'unknown'
        reasons = [System.Collections.Generic.List[string]]::new()
    }

    # Check 1: Is Parsec even running?
    $result.parsec_running = Test-ParsecProcessRunning
    if (-not $result.parsec_running) {
        $result.verdict = 'no_connection'
        $result.reasons.Add('Parsec process is not running.')
        return $result
    }

    # Check 2: Is there an active UDP stream?
    $result.active_stream = Test-ParsecActiveStream

    # Check 3: Is the last connect event stale?
    if ($LastConnectLine) {
        $result.connection_stale = Test-ParsecConnectionStale -LogLine $LastConnectLine -MaxAgeHours $MaxAgeHours

        # Check 4: Did the system reboot since the last connect event?
        $result.system_rebooted = Test-ParsecSystemRebootedSince -LogLine $LastConnectLine
    }

    # Verdict logic
    if ($result.active_stream) {
        $result.verdict = 'connected'
        $result.reasons.Add('Active UDP stream detected on parsecd process.')
    }
    elseif ($result.system_rebooted) {
        $result.verdict = 'no_connection'
        $result.reasons.Add('System rebooted since last connect event. Session is dead.')
    }
    elseif ($result.connection_stale) {
        $result.verdict = 'no_connection'
        $result.reasons.Add("Last connect event is older than $MaxAgeHours hours. Treating as stale.")
    }
    elseif (-not $LastConnectLine) {
        $result.verdict = 'no_connection'
        $result.reasons.Add('No connect event found in log history.')
    }
    else {
        # Parsec running, no active stream, recent connect, no reboot — ambiguous.
        # Could be a brief network hiccup. Trust the log.
        $result.verdict = 'possibly_connected'
        $result.reasons.Add('Parsec running but no active UDP stream. Log suggests connected. May be transient.')
    }

    return $result
}
