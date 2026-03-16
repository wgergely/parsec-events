$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

InModuleScope ParsecEventExecutor {
    Describe 'Invoke-ParsecWatcherReconcile' {
        It 'detects an active session from log tail' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-reconcile-$(New-Guid)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            $logFile = Join-Path $tempDir 'log.txt'

            try {
                $logContent = @(
                    '[D 2026-03-14 10:00:00] some noise line',
                    '[I 2026-03-14 10:00:01] wgergely#12571953 connected.',
                    '[D 2026-03-14 10:00:05] [0] FPS:30.0/0, L:5.0/10.0, B:1.0/5.0, N:0/0/0'
                ) -join "`n"
                Set-Content -LiteralPath $logFile -Value $logContent -NoNewline

                $patterns = [ordered]@{
                    connect = '\]\s+(.+#\d+)\s+connected\.\s*$'
                    disconnect = '\]\s+(.+#\d+)\s+disconnected\.\s*$'
                }
                $router = New-ParsecEventRouter -Patterns $patterns
                $tracker = New-ParsecSessionTracker -DefaultGracePeriodMs 10000

                Invoke-ParsecWatcherReconcile -LogPath $logFile -Router $router -Tracker $tracker -TailCount 100

                $tracker.active_sessions.Count | Should -Be 1
                $tracker.active_sessions.Contains('wgergely#12571953') | Should -BeTrue
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'does not detect a session that has already disconnected' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-reconcile-$(New-Guid)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            $logFile = Join-Path $tempDir 'log.txt'

            try {
                $logContent = @(
                    '[I 2026-03-14 10:00:01] wgergely#12571953 connected.',
                    '[D 2026-03-14 10:00:05] [0] FPS:30.0/0',
                    '[I 2026-03-14 10:05:00] wgergely#12571953 disconnected.'
                ) -join "`n"
                Set-Content -LiteralPath $logFile -Value $logContent -NoNewline

                $patterns = [ordered]@{
                    connect = '\]\s+(.+#\d+)\s+connected\.\s*$'
                    disconnect = '\]\s+(.+#\d+)\s+disconnected\.\s*$'
                }
                $router = New-ParsecEventRouter -Patterns $patterns
                $tracker = New-ParsecSessionTracker -DefaultGracePeriodMs 10000

                Invoke-ParsecWatcherReconcile -LogPath $logFile -Router $router -Tracker $tracker -TailCount 100

                $tracker.active_sessions.Count | Should -Be 0
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Describe 'EventRouter integration with real Parsec log data' {
        It 'correctly parses all connection events from the real Parsec log file' {
            $parsecLog = Join-Path -Path ([Environment]::GetFolderPath('CommonApplicationData')) -ChildPath 'Parsec\log.txt'

            if (-not (Test-Path -LiteralPath $parsecLog)) {
                Set-ItResult -Skipped -Because 'Parsec is not installed on this machine'
                return
            }

            $patterns = [ordered]@{
                connect = '\]\s+(.+#\d+)\s+connected\.\s*$'
                disconnect = '\]\s+(.+#\d+)\s+disconnected\.\s*$'
            }
            $router = New-ParsecEventRouter -Patterns $patterns

            $lines = @(Read-ParsecLogTailLines -LogPath $parsecLog -TailCount 10000)
            $connectCount = 0
            $disconnectCount = 0
            $noiseCount = 0

            foreach ($line in $lines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $parsed = Invoke-ParsecEventRouter -Router $router -Line $line

                if ($parsed) {
                    $parsed.username | Should -Match '.+#\d+'
                    $parsed.event_type | Should -BeIn @('connect', 'disconnect')

                    if ($parsed.event_type -eq 'connect') { $connectCount++ }
                    else { $disconnectCount++ }
                }
                else {
                    $noiseCount++
                }
            }

            $connectCount | Should -BeGreaterThan 0 -Because 'the real Parsec log should contain at least one connect event'
            $disconnectCount | Should -BeGreaterThan 0 -Because 'the real Parsec log should contain at least one disconnect event'
            $noiseCount | Should -BeGreaterThan $connectCount -Because 'most log lines are not connection events'

            Write-Information "Parsed $($lines.Count) lines: $connectCount connects, $disconnectCount disconnects, $noiseCount noise"
        }

        It 'does not match IPC or internal connect messages as user connections' {
            $parsecLog = Join-Path -Path ([Environment]::GetFolderPath('CommonApplicationData')) -ChildPath 'Parsec\log.txt'

            if (-not (Test-Path -LiteralPath $parsecLog)) {
                Set-ItResult -Skipped -Because 'Parsec is not installed on this machine'
                return
            }

            $patterns = [ordered]@{
                connect = '\]\s+(.+#\d+)\s+connected\.\s*$'
                disconnect = '\]\s+(.+#\d+)\s+disconnected\.\s*$'
            }
            $router = New-ParsecEventRouter -Patterns $patterns

            $lines = @(Read-ParsecLogTailLines -LogPath $parsecLog -TailCount 10000)

            foreach ($line in $lines) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                if ($line -match 'IPC.*Connected') {
                    $parsed = Invoke-ParsecEventRouter -Router $router -Line $line
                    $parsed | Should -BeNullOrEmpty -Because "IPC lines should not match: $line"
                }
            }
        }
    }

    Describe 'Full reconciliation against real Parsec log' {
        It 'reconciles the last session state from the real log' {
            $parsecLog = Join-Path -Path ([Environment]::GetFolderPath('CommonApplicationData')) -ChildPath 'Parsec\log.txt'

            if (-not (Test-Path -LiteralPath $parsecLog)) {
                Set-ItResult -Skipped -Because 'Parsec is not installed on this machine'
                return
            }

            $patterns = [ordered]@{
                connect = '\]\s+(.+#\d+)\s+connected\.\s*$'
                disconnect = '\]\s+(.+#\d+)\s+disconnected\.\s*$'
            }
            $router = New-ParsecEventRouter -Patterns $patterns
            $tracker = New-ParsecSessionTracker -DefaultGracePeriodMs 10000

            Invoke-ParsecWatcherReconcile -LogPath $parsecLog -Router $router -Tracker $tracker -TailCount 500

            $state = Get-ParsecSessionState -Tracker $tracker

            $state | Should -Not -BeNullOrEmpty
            $state.active_session_count | Should -BeOfType [int]

            Write-Information "Reconciliation: $($state.active_session_count) active session(s), usernames: $($state.active_usernames -join ', ')"
        }
    }

    Describe 'Start-ParsecWatcher public function' {
        It 'is exported from the module' {
            $cmd = Get-Command -Name Start-ParsecWatcher -Module ParsecEventExecutor -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Function'
        }

        It 'has the expected parameters' {
            $cmd = Get-Command -Name Start-ParsecWatcher -Module ParsecEventExecutor
            $cmd.Parameters.Keys | Should -Contain 'ConfigPath'
            $cmd.Parameters.Keys | Should -Contain 'StateRoot'
            $cmd.Parameters.Keys | Should -Contain 'DryRun'
        }
    }

    Describe 'Stop-ParsecWatcher public function' {
        It 'is exported from the module' {
            $cmd = Get-Command -Name Stop-ParsecWatcher -Module ParsecEventExecutor -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Function'
        }
    }

    Describe 'Register-ParsecWatcherTask public function' {
        It 'is exported from the module' {
            $cmd = Get-Command -Name Register-ParsecWatcherTask -Module ParsecEventExecutor -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Function'
        }

        It 'has the expected parameters' {
            $cmd = Get-Command -Name Register-ParsecWatcherTask -Module ParsecEventExecutor
            $cmd.Parameters.Keys | Should -Contain 'TaskName'
            $cmd.Parameters.Keys | Should -Contain 'ConfigPath'
            $cmd.Parameters.Keys | Should -Contain 'Force'
        }
    }

    Describe 'Unregister-ParsecWatcherTask public function' {
        It 'is exported from the module' {
            $cmd = Get-Command -Name Unregister-ParsecWatcherTask -Module ParsecEventExecutor -ErrorAction SilentlyContinue
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Function'
        }
    }

    Describe 'Watcher instance guard' {
        It 'prevents a second watcher from starting via mutex' {
            $mutexName = 'Global\ParsecEventWatcher_Test'
            $createdNew = $false
            $mutex = [System.Threading.Mutex]::new($true, $mutexName, [ref]$createdNew)

            try {
                $createdNew | Should -BeTrue

                $secondCreatedNew = $false
                $secondMutex = [System.Threading.Mutex]::new($true, $mutexName, [ref]$secondCreatedNew)

                try {
                    $secondCreatedNew | Should -BeFalse -Because 'a second mutex with the same name should not be newly created'
                }
                finally {
                    $secondMutex.Dispose()
                }
            }
            finally {
                $mutex.ReleaseMutex()
                $mutex.Dispose()
            }
        }
    }

    Describe 'Watcher config loads and validates against real Parsec log' {
        It 'default config resolves log path and compiles patterns that match real events' {
            $parsecLog = Join-Path -Path ([Environment]::GetFolderPath('CommonApplicationData')) -ChildPath 'Parsec\log.txt'

            if (-not (Test-Path -LiteralPath $parsecLog)) {
                Set-ItResult -Skipped -Because 'Parsec is not installed on this machine'
                return
            }

            $config = Read-ParsecWatcherConfig
            $resolvedPath = Resolve-ParsecLogPath -ConfiguredPath $config.watcher.parsec_log_path

            $resolvedPath | Should -Be $parsecLog

            $router = New-ParsecEventRouter -Patterns $config.patterns
            $lines = @(Read-ParsecLogTailLines -LogPath $resolvedPath -TailCount 1000)

            $matchCount = 0
            foreach ($line in $lines) {
                $parsed = Invoke-ParsecEventRouter -Router $router -Line $line
                if ($parsed) { $matchCount++ }
            }

            $matchCount | Should -BeGreaterThan 0 -Because 'the default regex patterns should match real Parsec events'
        }
    }
}
