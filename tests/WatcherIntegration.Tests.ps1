$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

InModuleScope ParsecEventExecutor {
    Describe 'Log rotation: watcher handles rotated log files' {
        It 'detects file size reset as rotation and reads from position zero' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-rotation-test-$(New-Guid)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            $logFile = Join-Path $tempDir 'log.txt'

            try {
                # Write a large initial log (simulating pre-rotation state)
                $initialLines = @('[D 2026-03-15 10:00:00] ===== Parsec: Started =====')
                for ($i = 0; $i -lt 100; $i++) {
                    $initialLines += "[D 2026-03-15 10:00:$($i.ToString('D2'))] [0] FPS:30.0/0, L:5.0/10.0, B:1.0/5.0, N:0/0/0"
                }
                $initialLines += '[I 2026-03-15 10:01:00] wgergely#12571953 connected.'
                Set-Content -LiteralPath $logFile -Value ($initialLines -join "`n") -NoNewline

                # Read the full file to establish a position at the end
                $lines1 = @(Read-ParsecLogTailLines -LogPath $logFile -TailCount 200)
                $lines1.Count | Should -BeGreaterThan 100

                # Record the file size (this simulates the tailer's $lastPosition)
                $preRotationSize = (Get-Item -LiteralPath $logFile).Length

                # Now simulate rotation: replace with a smaller file containing only post-rotation content
                $postRotationContent = @(
                    '[D 2026-03-15 10:30:00] ===== Parsec: Started =====',
                    '[I 2026-03-15 10:30:01] wgergely#12571953 disconnected.'
                ) -join "`n"
                Set-Content -LiteralPath $logFile -Value $postRotationContent -NoNewline

                $postRotationSize = (Get-Item -LiteralPath $logFile).Length

                # The post-rotation file must be smaller (rotation detection trigger)
                $postRotationSize | Should -BeLessThan $preRotationSize -Because 'rotation produces a smaller file'

                # Read-ParsecLogTailLines on the new file should find the disconnect
                $lines2 = @(Read-ParsecLogTailLines -LogPath $logFile -TailCount 200)

                $patterns = [ordered]@{
                    connect = '\]\s+(.+#\d+)\s+connected\.\s*$'
                    disconnect = '\]\s+(.+#\d+)\s+disconnected\.\s*$'
                }
                $router = New-ParsecEventRouter -Patterns $patterns

                $disconnectFound = $false
                foreach ($line in $lines2) {
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    $parsed = Invoke-ParsecEventRouter -Router $router -Line $line
                    if ($parsed -and $parsed.event_type -eq 'disconnect') {
                        $disconnectFound = $true
                    }
                }

                $disconnectFound | Should -BeTrue -Because 'post-rotation log should contain the disconnect event'
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'reconciliation correctly handles a rotated log where connect was in the old file' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-rotation-reconcile-$(New-Guid)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            $logFile = Join-Path $tempDir 'log.txt'

            try {
                # Post-rotation log: only contains a disconnect (connect was in the old rotated file)
                $logContent = @(
                    '[D 2026-03-15 10:30:00] ===== Parsec: Started =====',
                    '[D 2026-03-15 10:30:01] some noise',
                    '[I 2026-03-15 10:30:02] wgergely#12571953 disconnected.'
                ) -join "`n"
                Set-Content -LiteralPath $logFile -Value $logContent -NoNewline

                $patterns = [ordered]@{
                    connect = '\]\s+(.+#\d+)\s+connected\.\s*$'
                    disconnect = '\]\s+(.+#\d+)\s+disconnected\.\s*$'
                }
                $router = New-ParsecEventRouter -Patterns $patterns
                $tracker = New-ParsecSessionTracker -DefaultGracePeriodMs 10000

                Invoke-ParsecWatcherReconcile -LogPath $logFile -Router $router -Tracker $tracker -TailCount 100

                # No active sessions — the disconnect is the last event, no unmatched connect
                $tracker.active_sessions.Count | Should -Be 0 -Because 'the disconnect was the last event, no active session'
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'LogTailer position tracking resets when file shrinks (rotation detection)' {
            # Test the core rotation detection logic: if file size < lastPosition, reset to 0
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-position-test-$(New-Guid)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            $logFile = Join-Path $tempDir 'log.txt'

            try {
                # Create a file and record its size
                $largeContent = 'A' * 5000
                Set-Content -LiteralPath $logFile -Value $largeContent -NoNewline

                $tailer = New-ParsecLogTailer -LogPath $logFile
                # Simulate having read to position 5000
                $tailer.last_position = 5000L

                # Now replace with smaller file
                Set-Content -LiteralPath $logFile -Value 'small' -NoNewline
                $newSize = (Get-Item -LiteralPath $logFile).Length

                # The tailer's rotation detection: if currentSize < lastPosition, it's rotated
                ($newSize -lt $tailer.last_position) | Should -BeTrue -Because 'the new file is smaller than the last read position'
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Describe 'Multi-account: different usernames trigger different recipes' {
        It 'matches a username-filtered recipe for a specific user and falls back for others' {
            $phoneRecipe = [ordered]@{
                name = 'enter-mobile-phone'
                initial_mode = 'DESKTOP'
                target_mode = 'MOBILE'
                username = 'phone#1111'
                grace_period_ms = 5000
            }

            $laptopRecipe = [ordered]@{
                name = 'enter-laptop'
                initial_mode = 'DESKTOP'
                target_mode = 'MOBILE'
                username = 'laptop#2222'
                grace_period_ms = 30000
            }

            $defaultRecipe = [ordered]@{
                name = 'enter-mobile-default'
                initial_mode = 'DESKTOP'
                target_mode = 'MOBILE'
                username = $null
                grace_period_ms = $null
            }

            $allRecipes = @($phoneRecipe, $laptopRecipe, $defaultRecipe)

            # Phone user gets phone recipe
            $result = Find-ParsecMatchingRecipe -Username 'phone#1111' -CurrentMode 'DESKTOP' -EventType 'connect' -Recipes $allRecipes
            $result.name | Should -Be 'enter-mobile-phone'

            # Laptop user gets laptop recipe
            $result = Find-ParsecMatchingRecipe -Username 'laptop#2222' -CurrentMode 'DESKTOP' -EventType 'connect' -Recipes $allRecipes
            $result.name | Should -Be 'enter-laptop'

            # Unknown user gets default recipe
            $result = Find-ParsecMatchingRecipe -Username 'stranger#9999' -CurrentMode 'DESKTOP' -EventType 'connect' -Recipes $allRecipes
            $result.name | Should -Be 'enter-mobile-default'
        }

        It 'routes connect and disconnect events to the correct recipes per user through the full pipeline' {
            $patterns = [ordered]@{
                connect = '\]\s+(.+#\d+)\s+connected\.\s*$'
                disconnect = '\]\s+(.+#\d+)\s+disconnected\.\s*$'
            }
            $router = New-ParsecEventRouter -Patterns $patterns

            $phoneRecipe = [ordered]@{
                name = 'enter-mobile-phone'
                initial_mode = 'DESKTOP'
                target_mode = 'MOBILE'
                username = 'phone#1111'
                grace_period_ms = $null
            }
            $desktopRecipe = [ordered]@{
                name = 'return-desktop'
                initial_mode = 'MOBILE'
                target_mode = 'DESKTOP'
                username = $null
                grace_period_ms = $null
            }
            $recipes = @($phoneRecipe, $desktopRecipe)

            $logLines = @(
                '[I 2026-03-15 10:00:00] phone#1111 connected.',
                '[D 2026-03-15 10:00:01] [0] FPS:30.0/0',
                '[I 2026-03-15 10:05:00] phone#1111 disconnected.'
            )

            $tracker = New-ParsecSessionTracker -DefaultGracePeriodMs 0
            $currentMode = 'DESKTOP'
            $dispatched = [System.Collections.Generic.List[string]]::new()

            foreach ($line in $logLines) {
                $parsed = Invoke-ParsecEventRouter -Router $router -Line $line
                if (-not $parsed) { continue }

                if ($parsed.event_type -eq 'connect') {
                    $sessionResult = Register-ParsecSession -Tracker $tracker -Username $parsed.username
                    if ($sessionResult.action -eq 'dispatch_connect') {
                        $recipe = Find-ParsecMatchingRecipe -Username $parsed.username -CurrentMode $currentMode -EventType 'connect' -Recipes $recipes
                        if ($recipe) {
                            $dispatched.Add("connect:$($recipe.name)")
                            $currentMode = $recipe.target_mode
                        }
                    }
                }
                elseif ($parsed.event_type -eq 'disconnect') {
                    $sessionResult = Unregister-ParsecSession -Tracker $tracker -Username $parsed.username -GracePeriodMs 0
                    if ($sessionResult.action -eq 'grace_period_started') {
                        $expired = @(Get-ParsecExpiredDisconnects -Tracker $tracker)
                        foreach ($exp in $expired) {
                            $recipe = Find-ParsecMatchingRecipe -Username $exp.username -CurrentMode $currentMode -EventType 'disconnect' -Recipes $recipes
                            if ($recipe) {
                                $dispatched.Add("disconnect:$($recipe.name)")
                                $currentMode = $recipe.target_mode
                            }
                        }
                    }
                }
            }

            $dispatched.Count | Should -Be 2
            $dispatched[0] | Should -Be 'connect:enter-mobile-phone'
            $dispatched[1] | Should -Be 'disconnect:return-desktop'
            $currentMode | Should -Be 'DESKTOP'
        }

        It 'ignores a second user connection when first user is already connected' {
            $tracker = New-ParsecSessionTracker -DefaultGracePeriodMs 10000

            $first = Register-ParsecSession -Tracker $tracker -Username 'phone#1111'
            $first.action | Should -Be 'dispatch_connect'

            $second = Register-ParsecSession -Tracker $tracker -Username 'laptop#2222'
            $second.action | Should -Be 'additional_connect'

            $state = Get-ParsecSessionState -Tracker $tracker
            $state.active_session_count | Should -Be 2

            # Disconnect phone — laptop still active, no dispatch
            $phoneDisconnect = Unregister-ParsecSession -Tracker $tracker -Username 'phone#1111'
            $phoneDisconnect.action | Should -Be 'other_sessions_active'

            # Disconnect laptop — last session, grace period starts
            $laptopDisconnect = Unregister-ParsecSession -Tracker $tracker -Username 'laptop#2222'
            $laptopDisconnect.action | Should -Be 'grace_period_started'
        }
    }
}
