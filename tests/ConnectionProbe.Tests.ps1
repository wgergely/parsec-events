$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

InModuleScope ParsecEventExecutor {
    Describe 'Test-ParsecProcessRunning' {
        It 'detects whether parsecd is running on this system' {
            $result = Test-ParsecProcessRunning

            # We don't know if Parsec is running, but the function must return a boolean
            $result | Should -BeOfType [bool]
        }
    }

    Describe 'Test-ParsecActiveStream' {
        It 'returns a boolean indicating active UDP streams' {
            $result = Test-ParsecActiveStream
            $result | Should -BeOfType [bool]
        }
    }

    Describe 'Get-ParsecLastSystemBoot' {
        It 'returns the last boot time as a DateTimeOffset' {
            $result = Get-ParsecLastSystemBoot

            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [DateTimeOffset]
            $result | Should -BeLessThan ([DateTimeOffset]::Now)
        }
    }

    Describe 'Test-ParsecConnectionStale' {
        It 'returns false for a recent connect event' {
            $recentLine = "[I $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] test#1234 connected."
            $result = Test-ParsecConnectionStale -LogLine $recentLine -MaxAgeHours 72

            $result | Should -BeFalse
        }

        It 'returns true for an old connect event' {
            $oldLine = '[I 2020-01-01 00:00:00] test#1234 connected.'
            $result = Test-ParsecConnectionStale -LogLine $oldLine -MaxAgeHours 72

            $result | Should -BeTrue
        }

        It 'returns true for an unparseable line' {
            $result = Test-ParsecConnectionStale -LogLine 'garbage data' -MaxAgeHours 72

            $result | Should -BeTrue
        }
    }

    Describe 'Test-ParsecSystemRebootedSince' {
        It 'returns true for a connect event from before the last boot' {
            $lastBoot = Get-ParsecLastSystemBoot
            if (-not $lastBoot) {
                Set-ItResult -Skipped -Because 'Could not determine last boot time'
                return
            }

            $preBootTime = $lastBoot.AddHours(-1).ToString('yyyy-MM-dd HH:mm:ss')
            $line = "[I $preBootTime] test#1234 connected."

            $result = Test-ParsecSystemRebootedSince -LogLine $line
            $result | Should -BeTrue
        }

        It 'returns false for a connect event after the last boot' {
            $line = "[I $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] test#1234 connected."

            $result = Test-ParsecSystemRebootedSince -LogLine $line
            $result | Should -BeFalse
        }
    }

    Describe 'Invoke-ParsecConnectionProbe' {
        It 'returns a structured probe result' {
            $line = "[I $([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss'))] test#1234 connected."
            $result = Invoke-ParsecConnectionProbe -LastConnectLine $line -MaxAgeHours 72

            $result.verdict | Should -BeIn @('connected', 'possibly_connected', 'no_connection', 'unknown')
            $result.parsec_running | Should -BeOfType [bool]
            $result.active_stream | Should -BeOfType [bool]
            $result.connection_stale | Should -BeOfType [bool]
            $result.system_rebooted | Should -BeOfType [bool]
            $result.reasons.Count | Should -BeGreaterThan 0
        }

        It 'returns no_connection when no connect line is provided' {
            $result = Invoke-ParsecConnectionProbe -MaxAgeHours 72

            if ($result.parsec_running) {
                # Parsec is running but no connect line — depends on UDP state
                $result.verdict | Should -Not -Be 'unknown'
            }
            else {
                $result.verdict | Should -Be 'no_connection'
            }
        }

        It 'returns no_connection for a very old connect event' {
            $oldLine = '[I 2020-01-01 00:00:00] test#1234 connected.'
            $result = Invoke-ParsecConnectionProbe -LastConnectLine $oldLine -MaxAgeHours 72

            if (-not $result.parsec_running) {
                $result.verdict | Should -Be 'no_connection'
            }
            elseif (-not $result.active_stream) {
                $result.verdict | Should -Be 'no_connection'
                $result.connection_stale | Should -BeTrue
            }
        }
    }

    Describe 'Live connection probe against real Parsec' {
        It 'probes the real system and returns a coherent verdict' {
            $parsecLog = Join-Path -Path ([Environment]::GetFolderPath('CommonApplicationData')) -ChildPath 'Parsec\log.txt'

            if (-not (Test-Path -LiteralPath $parsecLog)) {
                Set-ItResult -Skipped -Because 'Parsec is not installed on this machine'
                return
            }

            $config = Read-ParsecWatcherConfig
            $router = New-ParsecEventRouter -Patterns $config.patterns
            $lines = @(Read-ParsecLogTailLines -LogPath $parsecLog -TailCount 500)

            # Find the last connect line
            $lastConnectLine = $null
            foreach ($line in $lines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $parsed = Invoke-ParsecEventRouter -Router $router -Line $line
                if ($parsed -and $parsed.event_type -eq 'connect') {
                    $lastConnectLine = $line
                }
            }

            $probe = Invoke-ParsecConnectionProbe -LastConnectLine $lastConnectLine -MaxAgeHours 72

            Write-Information "Live probe: verdict=$($probe.verdict), running=$($probe.parsec_running), stream=$($probe.active_stream), stale=$($probe.connection_stale), rebooted=$($probe.system_rebooted)"
            Write-Information "Reasons: $($probe.reasons -join '; ')"

            # The verdict must be one of the valid values
            $probe.verdict | Should -BeIn @('connected', 'possibly_connected', 'no_connection')

            # If Parsec is running and has a UDP stream, verdict must be connected
            if ($probe.parsec_running -and $probe.active_stream) {
                $probe.verdict | Should -Be 'connected'
            }

            # If Parsec is not running, verdict must be no_connection
            if (-not $probe.parsec_running) {
                $probe.verdict | Should -Be 'no_connection'
            }
        }
    }

    Describe 'Hardened reconciliation against real Parsec log' {
        It 'reconciles with probe validation and produces correct session state' {
            $parsecLog = Join-Path -Path ([Environment]::GetFolderPath('CommonApplicationData')) -ChildPath 'Parsec\log.txt'

            if (-not (Test-Path -LiteralPath $parsecLog)) {
                Set-ItResult -Skipped -Because 'Parsec is not installed on this machine'
                return
            }

            $config = Read-ParsecWatcherConfig
            $router = New-ParsecEventRouter -Patterns $config.patterns
            $tracker = New-ParsecSessionTracker -DefaultGracePeriodMs $config.watcher.grace_period_ms

            Invoke-ParsecWatcherReconcile -LogPath $parsecLog -Router $router -Tracker $tracker -TailCount 500

            $state = Get-ParsecSessionState -Tracker $tracker

            # If Parsec has an active stream, we should have detected it
            $hasStream = Test-ParsecActiveStream
            if ($hasStream) {
                $state.active_session_count | Should -BeGreaterThan 0 -Because 'an active UDP stream means someone is connected'
            }

            Write-Information "Hardened reconciliation: $($state.active_session_count) session(s), stream=$hasStream"
        }
    }
}
