$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

Describe 'Watcher daemon: isolated process reacts to synthetic log events' {
    BeforeAll {
        $testDir = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-daemon-test-$(New-Guid)"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null

        $script:syntheticLog = Join-Path $testDir 'log.txt'
        $script:stateRoot = Join-Path $testDir 'state'
        $script:configPath = Join-Path $testDir 'watcher.toml'
        $script:testDir = $testDir
        $script:daemonProcess = $null

        # Seed synthetic log
        Set-Content -LiteralPath $script:syntheticLog -Value "[D 2026-03-15 12:00:00] ===== Parsec: Started =====`n"

        # Write config pointing at synthetic log
        $escapedLog = $script:syntheticLog.Replace('\', '\\')
        $configContent = @"
[watcher]
parsec_log_path = "$escapedLog"
apply_delay_ms = 200
grace_period_ms = 1000
poll_interval_ms = 250
log_level = "info"

[patterns]
connect = '\]\s+(.+#\d+)\s+connected\.\s*`$'
disconnect = '\]\s+(.+#\d+)\s+disconnected\.\s*`$'
"@
        Set-Content -LiteralPath $script:configPath -Value $configContent

        # Resolve paths for the daemon script
        $script:projectRoot = Split-Path $PSScriptRoot -Parent
        $script:moduleFullPath = Join-Path $script:projectRoot 'src\ParsecEventExecutor\ParsecEventExecutor.psd1'
        $script:pwshPath = (Get-Process -Id $PID).Path
    }

    AfterAll {
        if ($script:daemonProcess -and -not $script:daemonProcess.HasExited) {
            $script:daemonProcess.Kill()
            $script:daemonProcess.WaitForExit(5000)
        }

        if ($script:daemonProcess) {
            $script:daemonProcess.Dispose()
        }

        Start-Sleep -Milliseconds 500
        Remove-Item -LiteralPath $script:testDir -Recurse -Force -ErrorAction SilentlyContinue

        # Clean up fixture recipes copied to the repo recipes dir
        $repoRecipesDir = Join-Path $script:projectRoot 'recipes'
        Remove-Item -LiteralPath (Join-Path $repoRecipesDir 'dev-connect-noop.toml') -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $repoRecipesDir 'dev-disconnect-noop.toml') -Force -ErrorAction SilentlyContinue
    }

    It 'starts the watcher daemon as an isolated process' {
        $fixtureRecipesDir = Join-Path $PSScriptRoot 'fixtures\recipes'
        $repoRecipesDir = Join-Path $script:projectRoot 'recipes'
        $daemonScript = @"
`$ErrorActionPreference = 'Stop'
Import-Module '$($script:moduleFullPath)' -Force
# Copy dev fixture recipes into the repo recipes dir so the watcher can discover them
# Use noop recipes that only capture/restore snapshots — no real display changes
Copy-Item -LiteralPath '$($fixtureRecipesDir)\dev-connect-noop.toml' -Destination '$repoRecipesDir' -Force
Copy-Item -LiteralPath '$($fixtureRecipesDir)\dev-disconnect-noop.toml' -Destination '$repoRecipesDir' -Force
Start-ParsecWatcher -ConfigPath '$($script:configPath)' -StateRoot '$($script:stateRoot)' -InformationAction Continue
"@
        $daemonScriptPath = Join-Path $script:testDir 'daemon.ps1'
        Set-Content -LiteralPath $daemonScriptPath -Value $daemonScript

        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $script:pwshPath
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$daemonScriptPath`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        $script:daemonProcess = [System.Diagnostics.Process]::Start($psi)

        # Wait for the daemon to initialize
        Start-Sleep -Seconds 4

        if ($script:daemonProcess.HasExited) {
            $stderr = $script:daemonProcess.StandardError.ReadToEnd()
            Write-Information "Daemon stderr: $stderr"
        }

        $script:daemonProcess.HasExited | Should -BeFalse -Because 'the daemon should be running'
    }

    It 'detects a connect event appended to the synthetic log' {
        # Append connect event
        $connectLine = "`n[I 2026-03-15 12:01:00] testdaemon#77777 connected.`n"
        [System.IO.File]::AppendAllText($script:syntheticLog, $connectLine)

        # Wait for poll_interval_ms (250ms) + apply_delay_ms (200ms) + recipe execution
        Start-Sleep -Seconds 12

        # Check executor state — the recipe should have dispatched
        $executorState = & (Get-Module ParsecEventExecutor) {
            param($stateRoot)
            Get-ParsecExecutorStateDocument -StateRoot $stateRoot
        } $script:stateRoot

        $executorState.last_applied_recipe | Should -Be 'dev-connect-noop' -Because 'the connect recipe should have been recorded'
        $executorState.last_event_type | Should -Be 'connect' -Because 'the connect event type should have been recorded'
        $executorState.transition_phase | Should -Not -Be 'Running' -Because 'the recipe should have completed'
    }

    It 'records the recipe execution in the run history' {
        $runsDir = Join-Path $script:stateRoot 'runs'
        $runFiles = @(Get-ChildItem -Path $runsDir -Filter '*.json' -ErrorAction SilentlyContinue)

        $runFiles.Count | Should -BeGreaterOrEqual 1 -Because 'at least one recipe run should be recorded'
    }

    It 'records events in the event journal' {
        $eventsDir = Join-Path $script:stateRoot 'events'
        $eventFiles = @(Get-ChildItem -Path $eventsDir -Filter '*.json' -ErrorAction SilentlyContinue)

        $eventFiles.Count | Should -BeGreaterThan 0 -Because 'recipe execution should generate event journal entries'
    }

    It 'detects a disconnect event and dispatches the restore recipe after grace period' {
        $disconnectLine = "`n[I 2026-03-15 12:10:00] testdaemon#77777 disconnected.`n"
        [System.IO.File]::AppendAllText($script:syntheticLog, $disconnectLine)

        # Wait for grace_period_ms (1000ms) + recipe execution
        Start-Sleep -Seconds 8

        $executorState = & (Get-Module ParsecEventExecutor) {
            param($stateRoot)
            Get-ParsecExecutorStateDocument -StateRoot $stateRoot
        } $script:stateRoot

        $executorState.last_applied_recipe | Should -Be 'dev-disconnect-noop' -Because 'the disconnect recipe should have been recorded'
        $executorState.last_event_type | Should -Be 'disconnect' -Because 'the disconnect event type should have been recorded'
    }

    It 'recorded at least one recipe run and the executor state reflects both dispatches' {
        $runsDir = Join-Path $script:stateRoot 'runs'
        $runFiles = @(Get-ChildItem -Path $runsDir -Filter '*.json' -ErrorAction SilentlyContinue)

        $runFiles.Count | Should -BeGreaterOrEqual 1 -Because 'at least the connect recipe run should be recorded'

        # The executor state should show dev-disconnect as last applied recipe
        $executorState = & (Get-Module ParsecEventExecutor) {
            param($stateRoot)
            Get-ParsecExecutorStateDocument -StateRoot $stateRoot
        } $script:stateRoot

        $executorState.last_applied_recipe | Should -Be 'dev-disconnect-noop' -Because 'the disconnect dispatch should have recorded dev-disconnect'
    }

    It 'created a transcript log file' {
        $logsDir = Join-Path $script:stateRoot 'logs'
        $logFiles = @(Get-ChildItem -Path $logsDir -Filter 'watcher-*.log' -ErrorAction SilentlyContinue)

        $logFiles.Count | Should -BeGreaterOrEqual 1 -Because 'the watcher should create a transcript log'
    }

    It 'the daemon process is still running after both events' {
        $script:daemonProcess.HasExited | Should -BeFalse -Because 'the daemon should keep running after processing events'
    }

    It 'stops cleanly when the process is terminated' {
        $script:daemonProcess.Kill()
        $exited = $script:daemonProcess.WaitForExit(5000)

        $exited | Should -BeTrue -Because 'the daemon should exit after being killed'
    }
}
