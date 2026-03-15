function Start-ParsecWatcherLoop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Config,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [switch] $DryRun
    )

    # --- Instance guard: prevent duplicate watchers ---
    $mutexName = 'Global\ParsecEventWatcher'
    $createdNew = $false
    $mutex = [System.Threading.Mutex]::new($true, $mutexName, [ref]$createdNew)

    if (-not $createdNew) {
        $mutex.Dispose()
        throw 'Another instance of the Parsec watcher is already running. Only one watcher is allowed at a time.'
    }

    # --- File logging ---
    $logsDir = Join-Path -Path $StateRoot -ChildPath 'logs'
    if (-not (Test-Path -LiteralPath $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    }

    $logTimestamp = [DateTime]::Now.ToString('yyyy-MM-dd_HH-mm-ss')
    $transcriptPath = Join-Path -Path $logsDir -ChildPath "watcher-$logTimestamp.log"

    try {
        Start-Transcript -LiteralPath $transcriptPath -Append | Out-Null
        Write-Information "Watcher: Transcript logging to '$transcriptPath'"
    }
    catch {
        Write-Warning "Watcher: Could not start transcript logging: $_"
    }

    # Clean old log files (keep last 10)
    $oldLogs = Get-ChildItem -Path $logsDir -Filter 'watcher-*.log' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip 10
    foreach ($old in $oldLogs) {
        Remove-Item -LiteralPath $old.FullName -Force -ErrorAction SilentlyContinue
    }

    $logPath = Resolve-ParsecLogPath -ConfiguredPath $Config.watcher.parsec_log_path
    Write-Information "Watcher: Parsec log path resolved to '$logPath'"

    $recipes = @(Get-ParsecRecipe)
    if ($recipes.Count -eq 0) {
        throw 'No recipes found. Cannot start watcher without at least one recipe.'
    }

    Write-Information "Watcher: Loaded $($recipes.Count) recipe(s): $($recipes.name -join ', ')"

    Initialize-ParsecStateRoot -StateRoot $StateRoot | Out-Null

    $router = New-ParsecEventRouter -Patterns $Config.patterns
    $tracker = New-ParsecSessionTracker -DefaultGracePeriodMs $Config.watcher.grace_period_ms
    $dispatcher = New-ParsecWatcherDispatcher -StateRoot $StateRoot
    $tailer = New-ParsecLogTailer -LogPath $logPath -PollIntervalMs $Config.watcher.poll_interval_ms

    $executorState = Get-ParsecExecutorStateDocument -StateRoot $StateRoot
    $currentMode = if ($executorState.desired_mode) { $executorState.desired_mode } else { 'DESKTOP' }
    Write-Information "Watcher: Initial mode is '$currentMode'"

    Invoke-ParsecWatcherReconcile -LogPath $logPath -Router $router -Tracker $tracker -TailCount 200
    Write-Information "Watcher: Startup reconciliation complete. Active sessions: $($tracker.active_sessions.Count)"

    # Pending connect events waiting for apply_delay_ms to expire
    $pendingConnects = [System.Collections.Generic.List[hashtable]]::new()

    # Incoming log line queue — event handler only enqueues, main loop processes
    $incomingLines = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

    # Set up script-scope state BEFORE registering any events (fixes race condition)
    $script:ParsecWatcherIncomingLines = $incomingLines

    Start-ParsecLogTailer -Tailer $tailer -SkipExisting

    # Lightweight handler: only enqueues raw lines, no processing
    Register-EngineEvent -SourceIdentifier 'Parsec.LogLine' -Action {
        $line = $Event.MessageData.Line
        if ($line -and $script:ParsecWatcherIncomingLines) {
            $script:ParsecWatcherIncomingLines.Enqueue($line)
        }
    } | Out-Null

    Write-Information 'Watcher: Log tailer started. Entering event loop.'

    $watcherState = [ordered]@{
        current_mode = $currentMode
        is_running = $true
        started_at = [DateTimeOffset]::UtcNow.ToString('o')
        events_processed = 0
        recipes_dispatched = 0
    }

    # Expose for Stop-ParsecWatcherLoop
    $script:ParsecWatcherState = $watcherState

    try {
        while ($watcherState.is_running) {
            # --- Phase 1: Drain incoming log lines and route events ---
            $line = $null
            while ($incomingLines.TryDequeue([ref]$line)) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }

                $parsedEvent = Invoke-ParsecEventRouter -Router $router -Line $line
                if (-not $parsedEvent) { continue }

                $watcherState.events_processed++
                $username = $parsedEvent.username
                $eventType = $parsedEvent.event_type

                Write-Information "Watcher: Detected $eventType event for '$username'"

                if ($eventType -eq 'connect') {
                    $sessionResult = Register-ParsecSession -Tracker $tracker -Username $username

                    if ($sessionResult.action -eq 'dispatch_connect') {
                        $recipe = Find-ParsecMatchingRecipe -Username $username -CurrentMode $watcherState.current_mode -EventType 'connect' -Recipes $recipes

                        if ($recipe) {
                            $delayMs = $Config.watcher.apply_delay_ms
                            Write-Information "Watcher: Matched recipe '$($recipe.name)' for connect from '$username' (delay: ${delayMs}ms)"

                            # Queue the connect for delayed dispatch instead of sleeping
                            $pendingConnects.Add(@{
                                    recipe = $recipe
                                    username = $username
                                    dispatch_at = [DateTimeOffset]::UtcNow.AddMilliseconds($delayMs)
                                })
                        }
                        else {
                            Write-Information "Watcher: No matching recipe for connect from '$username' in mode '$($watcherState.current_mode)'"
                        }
                    }
                    else {
                        Write-Information "Watcher: $($sessionResult.message)"
                    }
                }
                elseif ($eventType -eq 'disconnect') {
                    $recipe = Find-ParsecMatchingRecipe -Username $username -CurrentMode $watcherState.current_mode -EventType 'disconnect' -Recipes $recipes
                    $gracePeriod = if ($recipe) {
                        Get-ParsecRecipeGracePeriod -Recipe $recipe -DefaultGracePeriodMs $Config.watcher.grace_period_ms
                    }
                    else {
                        $Config.watcher.grace_period_ms
                    }

                    $sessionResult = Unregister-ParsecSession -Tracker $tracker -Username $username -GracePeriodMs $gracePeriod
                    Write-Information "Watcher: $($sessionResult.message)"
                }
            }

            # --- Phase 2: Dispatch pending connects whose delay has elapsed ---
            $now = [DateTimeOffset]::UtcNow
            for ($i = $pendingConnects.Count - 1; $i -ge 0; $i--) {
                $pending = $pendingConnects[$i]
                if ($now -lt $pending.dispatch_at) { continue }

                $pendingConnects.RemoveAt($i)
                $recipe = $pending.recipe
                $username = $pending.username

                if ($DryRun) {
                    Write-Information "Watcher: [DRY RUN] Would dispatch recipe '$($recipe.name)' for '$username'"
                }
                else {
                    $dispatchResult = Invoke-ParsecWatcherDispatch -Dispatcher $dispatcher -Recipe $recipe -Username $username -EventType 'connect'
                    if ($dispatchResult.status -eq 'Dispatched' -and $dispatchResult.terminal_status -in @('Succeeded', 'SucceededWithDrift', 'Compensated')) {
                        $watcherState.current_mode = $recipe.target_mode
                        $watcherState.recipes_dispatched++
                    }
                }
            }

            # --- Phase 3: Check expired grace periods ---
            $expired = @(Get-ParsecExpiredDisconnects -Tracker $tracker)
            foreach ($expiredEvent in $expired) {
                $username = $expiredEvent.username
                Write-Information "Watcher: Grace period expired for '$username'. Looking for disconnect recipe."

                $recipe = Find-ParsecMatchingRecipe -Username $username -CurrentMode $watcherState.current_mode -EventType 'disconnect' -Recipes $recipes

                if ($recipe) {
                    if ($DryRun) {
                        Write-Information "Watcher: [DRY RUN] Would dispatch disconnect recipe '$($recipe.name)'"
                    }
                    else {
                        $dispatchResult = Invoke-ParsecWatcherDispatch -Dispatcher $dispatcher -Recipe $recipe -Username $username -EventType 'disconnect'
                        if ($dispatchResult.status -eq 'Dispatched' -and $dispatchResult.terminal_status -in @('Succeeded', 'SucceededWithDrift', 'Compensated')) {
                            $watcherState.current_mode = $recipe.target_mode
                            $watcherState.recipes_dispatched++
                        }
                    }
                }
                else {
                    Write-Information "Watcher: No matching disconnect recipe for '$username' in mode '$($watcherState.current_mode)'"
                }
            }

            # --- Phase 4: Drain dispatch queue ---
            if (-not $dispatcher.is_busy) {
                $drainResults = @(Invoke-ParsecWatcherDrainQueue -Dispatcher $dispatcher)
                foreach ($dr in $drainResults) {
                    if ($dr.status -eq 'Dispatched' -and $dr.terminal_status -in @('Succeeded', 'SucceededWithDrift', 'Compensated')) {
                        $watcherState.current_mode = $dr.result.target_mode
                        $watcherState.recipes_dispatched++
                    }
                }
            }

            # Sleep briefly to avoid busy-waiting. Events accumulate in the
            # ConcurrentQueue and are drained on the next iteration.
            Start-Sleep -Milliseconds 250
        }
    }
    finally {
        Write-Information 'Watcher: Shutting down...'
        Stop-ParsecLogTailer -Tailer $tailer
        Unregister-Event -SourceIdentifier 'Parsec.LogLine' -ErrorAction SilentlyContinue
        Remove-Job -Name 'Parsec.LogLine' -ErrorAction SilentlyContinue
        $script:ParsecWatcherIncomingLines = $null
        $script:ParsecWatcherState = $null

        if ($mutex) {
            $mutex.ReleaseMutex()
            $mutex.Dispose()
        }

        Write-Information "Watcher: Stopped. Processed $($watcherState.events_processed) events, dispatched $($watcherState.recipes_dispatched) recipes."

        try { Stop-Transcript -ErrorAction SilentlyContinue } catch { Write-Debug "Transcript stop: $_" }
    }

    return [ordered]@{
        events_processed = $watcherState.events_processed
        recipes_dispatched = $watcherState.recipes_dispatched
        started_at = $watcherState.started_at
        stopped_at = [DateTimeOffset]::UtcNow.ToString('o')
    }
}

function Stop-ParsecWatcherLoop {
    [CmdletBinding()]
    param()

    if ($script:ParsecWatcherState) {
        $script:ParsecWatcherState.is_running = $false
        Write-Information 'Watcher: Stop requested.'
    }
}

function Invoke-ParsecWatcherReconcile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $LogPath,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Router,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Tracker,

        [Parameter()]
        [int] $TailCount = 200,

        [Parameter()]
        [int] $MaxStaleHours = 72
    )

    $tailLines = @(Read-ParsecLogTailLines -LogPath $LogPath -TailCount $TailCount)

    # Track the last event per username, keeping the raw line for timestamp analysis.
    $lastEvent = @{}
    $lastConnectLine = @{}

    foreach ($line in $tailLines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parsed = Invoke-ParsecEventRouter -Router $Router -Line $line
        if (-not $parsed) { continue }

        $lastEvent[$parsed.username] = $parsed.event_type
        if ($parsed.event_type -eq 'connect') {
            $lastConnectLine[$parsed.username] = $line
        }
    }

    # Identify users whose last log event was a connect (potentially still connected)
    $candidateUsers = @(@($lastEvent.Keys) | Where-Object { $lastEvent[$_] -eq 'connect' })

    if ($candidateUsers.Count -eq 0) {
        Write-Information 'Watcher: Reconciliation found no unmatched connect events.'
        return
    }

    foreach ($username in $candidateUsers) {
        $connectLine = $lastConnectLine[$username]

        # Run the multi-layer connection probe to validate
        $probe = Invoke-ParsecConnectionProbe -LastConnectLine $connectLine -MaxAgeHours $MaxStaleHours

        Write-Information "Watcher: Reconciliation probe for '$username': verdict=$($probe.verdict), reasons=$($probe.reasons -join '; ')"

        if ($probe.verdict -eq 'connected') {
            $Tracker.active_sessions[$username] = [ordered]@{
                connected_at = [DateTimeOffset]::UtcNow.ToString('o')
            }

            Write-Warning "Watcher: Reconciliation confirmed active session for '$username' (UDP stream detected)."
        }
        elseif ($probe.verdict -eq 'possibly_connected') {
            # Parsec running, no UDP stream, but log says connected and no reboot.
            # Trust the log but warn — could be a brief network gap.
            $Tracker.active_sessions[$username] = [ordered]@{
                connected_at = [DateTimeOffset]::UtcNow.ToString('o')
            }

            Write-Warning "Watcher: Reconciliation accepted session for '$username' (log-based, no UDP confirmation). May be stale."
        }
        else {
            # no_connection: Parsec not running, session stale, or system rebooted
            Write-Information "Watcher: Reconciliation rejected stale session for '$username': $($probe.reasons -join '; ')"
        }
    }
}
