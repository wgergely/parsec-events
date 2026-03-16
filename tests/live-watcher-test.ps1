# Live watcher pipeline test
# Exercises the full watcher pipeline synchronously: log tailing → event routing
# → session tracking → recipe matching → dispatch. Uses a synthetic log file
# and safe snapshot-only recipes. Does not require Parsec connection.

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$projectRoot = Split-Path $PSScriptRoot -Parent
$modulePath = Join-Path $projectRoot 'src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-live-pipeline-$(New-Guid)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$stateRoot = Join-Path $tempDir 'state'

& (Get-Module ParsecEventExecutor) {
    param($stateRoot)
    Initialize-ParsecStateRoot -StateRoot $stateRoot | Out-Null
} $stateRoot

try {
    Write-Information '=== Live Watcher Pipeline Test ==='
    Write-Information ''

    $config = & (Get-Module ParsecEventExecutor) { Read-ParsecWatcherConfig }
    $router = & (Get-Module ParsecEventExecutor) {
        param($patterns)
        New-ParsecEventRouter -Patterns $patterns
    } $config.patterns

    $tracker = & (Get-Module ParsecEventExecutor) {
        param($gracePeriod)
        New-ParsecSessionTracker -DefaultGracePeriodMs $gracePeriod
    } $config.watcher.grace_period_ms

    $recipes = @(Get-ParsecRecipe)
    $dispatcher = & (Get-Module ParsecEventExecutor) {
        param($stateRoot)
        New-ParsecWatcherDispatcher -StateRoot $stateRoot
    } $stateRoot

    $currentMode = 'DESKTOP'

    Write-Information "Loaded $($recipes.Count) recipes: $($recipes.name -join ', ')"
    Write-Information "Initial mode: $currentMode"
    Write-Information ''

    # --- Phase 1: Connect event ---
    Write-Information '--- Phase 1: Connect ---'
    $connectLine = '[I 2026-03-15 12:01:00] wgergely#12571953 connected.'
    $parsed = & (Get-Module ParsecEventExecutor) {
        param($router, $line)
        Invoke-ParsecEventRouter -Router $router -Line $line
    } $router $connectLine

    Write-Information "Parsed: event=$($parsed.event_type), user=$($parsed.username)"

    $sessionResult = & (Get-Module ParsecEventExecutor) {
        param($tracker, $username)
        Register-ParsecSession -Tracker $tracker -Username $username
    } $tracker $parsed.username

    Write-Information "Session: action=$($sessionResult.action)"

    if ($sessionResult.action -eq 'dispatch_connect') {
        $recipe = & (Get-Module ParsecEventExecutor) {
            param($username, $currentMode, $recipes)
            Find-ParsecMatchingRecipe -Username $username -CurrentMode $currentMode -EventType 'connect' -Recipes $recipes
        } $parsed.username $currentMode $recipes

        if ($recipe) {
            Write-Information "Matched recipe: $($recipe.name) (target: $($recipe.target_mode))"

            $dispatchResult = & (Get-Module ParsecEventExecutor) {
                param($dispatcher, $recipe, $username)
                Invoke-ParsecWatcherDispatch -Dispatcher $dispatcher -Recipe $recipe -Username $username -EventType 'connect'
            } $dispatcher $recipe $parsed.username

            Write-Information "Dispatch: status=$($dispatchResult.status), terminal=$($dispatchResult.terminal_status)"

            if ($dispatchResult.status -eq 'Dispatched' -and $dispatchResult.terminal_status -in @('Succeeded', 'SucceededWithDrift', 'Compensated')) {
                $currentMode = $recipe.target_mode
                Write-Information "Mode changed: $currentMode"
            }
            else {
                Write-Information "Dispatch did not succeed: $($dispatchResult.message)"
            }
        }
    }

    Write-Information ''

    # --- Phase 2: Disconnect event ---
    Write-Information '--- Phase 2: Disconnect ---'
    $disconnectLine = '[I 2026-03-15 12:10:00] wgergely#12571953 disconnected.'
    $parsed = & (Get-Module ParsecEventExecutor) {
        param($router, $line)
        Invoke-ParsecEventRouter -Router $router -Line $line
    } $router $disconnectLine

    Write-Information "Parsed: event=$($parsed.event_type), user=$($parsed.username)"

    $disconnectRecipe = & (Get-Module ParsecEventExecutor) {
        param($username, $currentMode, $recipes)
        Find-ParsecMatchingRecipe -Username $username -CurrentMode $currentMode -EventType 'disconnect' -Recipes $recipes
    } $parsed.username $currentMode $recipes

    $gracePeriod = if ($disconnectRecipe) {
        & (Get-Module ParsecEventExecutor) {
            param($recipe, $default)
            Get-ParsecRecipeGracePeriod -Recipe $recipe -DefaultGracePeriodMs $default
        } $disconnectRecipe $config.watcher.grace_period_ms
    }
    else { $config.watcher.grace_period_ms }

    # Use 0 grace period for the test
    $sessionResult = & (Get-Module ParsecEventExecutor) {
        param($tracker, $username)
        Unregister-ParsecSession -Tracker $tracker -Username $username -GracePeriodMs 0
    } $tracker $parsed.username

    Write-Information "Session: action=$($sessionResult.action)"

    # Check expired
    Start-Sleep -Milliseconds 100
    $expired = @(& (Get-Module ParsecEventExecutor) {
            param($tracker)
            Get-ParsecExpiredDisconnects -Tracker $tracker
        } $tracker)

    if ($expired.Count -gt 0 -and $disconnectRecipe) {
        Write-Information "Grace period expired. Matched recipe: $($disconnectRecipe.name)"

        $dispatchResult = & (Get-Module ParsecEventExecutor) {
            param($dispatcher, $recipe, $username)
            Invoke-ParsecWatcherDispatch -Dispatcher $dispatcher -Recipe $recipe -Username $username -EventType 'disconnect'
        } $dispatcher $disconnectRecipe $expired[0].username

        Write-Information "Dispatch: status=$($dispatchResult.status), terminal=$($dispatchResult.terminal_status)"

        if ($dispatchResult.status -eq 'Dispatched' -and $dispatchResult.terminal_status -in @('Succeeded', 'SucceededWithDrift', 'Compensated')) {
            $currentMode = $disconnectRecipe.target_mode
            Write-Information "Mode restored: $currentMode"
        }
    }

    # --- Results ---
    Write-Information ''
    Write-Information '--- Final State ---'

    $executorState = & (Get-Module ParsecEventExecutor) {
        param($stateRoot)
        Get-ParsecExecutorStateDocument -StateRoot $stateRoot
    } $stateRoot

    Write-Information "desired_mode:     $($executorState.desired_mode)"
    Write-Information "transition_phase: $($executorState.transition_phase)"
    Write-Information "active_snapshot:  $($executorState.active_snapshot)"

    $runFiles = @(Get-ChildItem -Path (Join-Path $stateRoot 'runs') -Filter '*.json' -ErrorAction SilentlyContinue)
    $eventFiles = @(Get-ChildItem -Path (Join-Path $stateRoot 'events') -Filter '*.json' -ErrorAction SilentlyContinue)
    Write-Information "Runs recorded:    $($runFiles.Count)"
    Write-Information "Events recorded:  $($eventFiles.Count)"

    Write-Information ''
    if ($currentMode -eq 'DESKTOP' -and $runFiles.Count -ge 2) {
        Write-Information '=== FULL PIPELINE TEST PASSED ==='
        Write-Information 'Connect dispatched, mode changed to MOBILE, disconnect dispatched, mode restored to DESKTOP.'
    }
    else {
        Write-Information "=== TEST INCOMPLETE: mode=$currentMode, runs=$($runFiles.Count) ==="
    }
}
finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
