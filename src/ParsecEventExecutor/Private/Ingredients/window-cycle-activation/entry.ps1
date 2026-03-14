param(
    [Parameter()]
    [System.Collections.IDictionary] $Schema,

    [Parameter()]
    [string] $IngredientPath
)

$supportFiles = @(
    (Join-Path -Path (Split-Path -Path $IngredientPath -Parent) -ChildPath '..\Utility.ps1'),
    (Join-Path -Path (Split-Path -Path $IngredientPath -Parent) -ChildPath '..\Core\HostSupport.ps1'),
    (Join-Path -Path (Split-Path -Path $IngredientPath -Parent) -ChildPath '..\Domains\display\Platform.ps1')
)

foreach ($file in @($supportFiles)) { . $file }

$invokeWindowAdapter = {
    param(
        [string] $Method,
        [hashtable] $Arguments = @{}
    )

    $adapter = $null
    if (Get-Command -Name 'Get-ParsecModuleVariableValue' -ErrorAction SilentlyContinue) {
        $adapter = Get-ParsecModuleVariableValue -Name 'ParsecWindowAdapter'
    }

    if ($null -eq $adapter) {
        $adapterVar = Get-Variable -Name 'ParsecWindowAdapter' -Scope Global -ErrorAction SilentlyContinue
        if ($null -ne $adapterVar) {
            $adapter = $adapterVar.Value
        }
    }

    if ($null -ne $adapter -and $adapter.ContainsKey($Method)) {
        return & $adapter[$Method] $Arguments
    }

    if (Get-Command -Name 'Initialize-ParsecDisplayInterop' -ErrorAction SilentlyContinue) {
        Initialize-ParsecDisplayInterop
    }

    switch ($Method) {
        'GetForegroundWindowInfo' {
            return [ParsecEventExecutor.DisplayNative]::GetForegroundWindowCapture()
        }
        'GetTopLevelWindows' {
            return @([ParsecEventExecutor.DisplayNative]::GetTopLevelWindows())
        }
        'ActivateWindow' {
            $handle = [int64] $Arguments.handle
            $succeeded = [bool] [ParsecEventExecutor.DisplayNative]::ActivateWindow($handle, [bool] $Arguments.restore_if_minimized)
            return [ordered]@{
                succeeded = $succeeded
                handle = $handle
                window = [ParsecEventExecutor.DisplayNative]::GetForegroundWindowCapture()
            }
        }
        default {
            throw "Window adapter method '$Method' is not available."
        }
    }
}.GetNewClosure()

$toPlain = {
    param($InputObject)
    if (Get-Command -Name 'ConvertTo-ParsecPlainObject' -ErrorAction SilentlyContinue) {
        return ConvertTo-ParsecPlainObject -InputObject $InputObject
    }

    return $InputObject
}.GetNewClosure()

$newResult = {
    param(
        [Parameter(Mandatory)]
        [string] $Status,

        [Parameter()]
        [string] $Message = '',

        [Parameter()]
        [System.Collections.IDictionary] $Requested = @{},

        [Parameter()]
        [System.Collections.IDictionary] $Observed = @{},

        [Parameter()]
        [System.Collections.IDictionary] $Outputs = @{},

        [Parameter()]
        [string[]] $Warnings = @(),

        [Parameter()]
        [string[]] $Errors = @(),

        [Parameter()]
        [bool] $CanCompensate = $false
    )

    if (Get-Command -Name 'New-ParsecResult' -ErrorAction SilentlyContinue) {
        return New-ParsecResult -Status $Status -Message $Message -Requested ([hashtable] (& $toPlain $Requested)) -Observed ([hashtable] (& $toPlain $Observed)) -Outputs ([hashtable] (& $toPlain $Outputs)) -Warnings $Warnings -Errors $Errors -CanCompensate $CanCompensate
    }

    return [pscustomobject]@{
        PSTypeName    = 'ParsecEventExecutor.Result'
        Status        = $Status
        Message       = $Message
        Requested     = & $toPlain $Requested
        Observed      = & $toPlain $Observed
        Outputs       = & $toPlain $Outputs
        Warnings      = @($Warnings)
        Errors        = @($Errors)
        CanCompensate = $CanCompensate
        Timestamp     = [DateTimeOffset]::UtcNow.ToString('o')
    }
}.GetNewClosure()

$getCapturedState = {
    param(
        [System.Collections.IDictionary] $Arguments,
        $ExecutionResult
    )

    if ($Arguments.Contains('captured_state') -and $Arguments.captured_state -is [System.Collections.IDictionary]) {
        return & $toPlain $Arguments.captured_state
    }

    if ($null -ne $ExecutionResult -and $ExecutionResult.Outputs -and $ExecutionResult.Outputs.captured_state) {
        return & $toPlain $ExecutionResult.Outputs.captured_state
    }

    return $null
}.GetNewClosure()

$isActivationCandidate = {
    param([System.Collections.IDictionary] $Window)

    if ($null -eq $Window.handle -or [int64] $Window.handle -eq 0) { return $false }
    if ($Window.Contains('is_shell_window') -and [bool] $Window.is_shell_window) { return $false }
    if ($Window.Contains('is_visible') -and -not [bool] $Window.is_visible) { return $false }
    if ($Window.Contains('is_cloaked') -and [bool] $Window.is_cloaked) { return $false }
    if ($Window.Contains('is_on_input_desktop') -and -not [bool] $Window.is_on_input_desktop) { return $false }
    if ($Window.Contains('is_on_current_virtual_desktop') -and -not [bool] $Window.is_on_current_virtual_desktop) { return $false }
    if ($Window.Contains('is_minimized') -and [bool] $Window.is_minimized) { return $false }

    $title = if ($Window.Contains('title')) { [string] $Window.title } else { '' }
    if ([string]::IsNullOrWhiteSpace($title)) { return $false }

    $className = if ($Window.Contains('class_name')) { [string] $Window.class_name } else { '' }
    if ($className -in @('IME', 'tooltips_class32', 'SysShadow', 'ForegroundStaging', 'ThumbnailDeviceHelperWnd', 'PseudoConsoleWindow')) { return $false }

    $processName = if ($Window.Contains('process_name')) { [string] $Window.process_name } else { '' }
    if ($processName -eq 'ApplicationFrameHost') { return $false }
    if ($title -eq 'Windows Input Experience' -or $processName -eq 'TextInputHost') { return $false }

    $extendedStyle = if ($Window.Contains('extended_style') -and $null -ne $Window.extended_style) { [int64] $Window.extended_style } else { 0 }
    $ownerHandle = if ($Window.Contains('owner_handle') -and $null -ne $Window.owner_handle) { [int64] $Window.owner_handle } else { 0 }
    $hasAppWindowStyle = ($extendedStyle -band 0x40000) -ne 0
    $hasToolWindowStyle = ($extendedStyle -band 0x80) -ne 0
    $hasNoActivateStyle = ($extendedStyle -band 0x08000000) -ne 0
    $hasTopMostStyle = ($extendedStyle -band 0x8) -ne 0

    $width = if ($Window.Contains('width') -and $null -ne $Window.width) { [int] $Window.width } else { 0 }
    $height = if ($Window.Contains('height') -and $null -ne $Window.height) { [int] $Window.height } else { 0 }
    if ($width -gt 0 -and $height -gt 0 -and ($width -lt 64 -or $height -lt 64)) { return $false }
    if (($extendedStyle -band 0x80) -ne 0) { return $false }
    if ($hasNoActivateStyle) { return $false }
    if ($ownerHandle -ne 0 -and -not $hasAppWindowStyle) { return $false }
    if ($hasToolWindowStyle) { return $false }
    if ($hasTopMostStyle) { return $false }

    return $true
}.GetNewClosure()

$captureState = {
    $foreground = $null
    foreach ($attempt in 1..5) {
        $foreground = & $invokeWindowAdapter 'GetForegroundWindowInfo' @{}
        if ($null -ne $foreground -and $foreground.handle) {
            break
        }

        Start-Sleep -Milliseconds 100
    }

    $windows = @(& $invokeWindowAdapter 'GetTopLevelWindows' @{})
    $candidates = @(
        foreach ($window in $windows) {
            $plainWindow = & $toPlain $window
            if (& $isActivationCandidate $plainWindow) {
                $plainWindow
            }
        }
    )

    return [ordered]@{
        captured_at = [DateTimeOffset]::UtcNow.ToString('o')
        foreground_window = & $toPlain $foreground
        windows = @($candidates | ForEach-Object { & $toPlain $_ })
    }
}.GetNewClosure()

$applyCycle = {
    param([System.Collections.IDictionary] $Arguments = @{})

    $dwellMilliseconds = if ($Arguments.Contains('dwell_ms')) { [int] $Arguments.dwell_ms } else { 100 }
    if ($dwellMilliseconds -lt 0) { throw 'dwell_ms must be zero or greater.' }

    $maxCycles = if ($Arguments.Contains('max_cycles')) { [int] $Arguments.max_cycles } else { 30 }
    if ($maxCycles -lt 1) { throw 'max_cycles must be one or greater.' }

    $capture = & $captureState
    $foregroundWindow = if ($capture.Contains('foreground_window')) { & $toPlain $capture.foreground_window } else { $null }
    $foregroundHandle = if ($foregroundWindow -is [System.Collections.IDictionary] -and $foregroundWindow.Contains('handle') -and $null -ne $foregroundWindow.handle) { [int64] $foregroundWindow.handle } else { 0 }
    if ($foregroundHandle -eq 0) {
        return & $newResult -Status 'Failed' -Message 'Could not capture the current foreground window.' -Errors @('MissingForegroundWindow')
    }

    $altTabCandidates = if ($capture.Contains('windows')) { @($capture.windows) } else { @() }
    $candidateHandles = @($altTabCandidates | ForEach-Object { if ($_ -is [System.Collections.IDictionary] -and $_.Contains('handle')) { [int64] $_.handle } })
    if ($candidateHandles.Count -eq 0) {
        return & $newResult -Status 'Failed' -Message 'No Alt-Tab candidate windows were available to cycle.' -Observed @{ foreground_window = $foregroundWindow } -Errors @('MissingAltTabCandidates')
    }

    if (-not ($candidateHandles -contains $foregroundHandle)) {
        return & $newResult -Status 'Failed' -Message 'The current foreground window is not an Alt-Tab candidate.' -Observed @{
            foreground_window = $foregroundWindow
            candidate_handles = @($candidateHandles)
        } -Errors @('ForegroundNotAltTabCandidate')
    }

    $activationResults = New-Object System.Collections.ArrayList
    $candidateSequence = @($altTabCandidates | Where-Object {
            $_ -is [System.Collections.IDictionary] -and $_.Contains('handle') -and [int64] $_.handle -ne $foregroundHandle
        })
    if ($candidateSequence.Count -gt $maxCycles) {
        $candidateSequence = @($candidateSequence | Select-Object -First $maxCycles)
    }

    $activationSucceeded = $true
    $cycle = 0
    foreach ($candidate in $candidateSequence) {
        $cycle++
        $activation = & $invokeWindowAdapter 'ActivateWindow' @{
            handle = [int64] $candidate.handle
            restore_if_minimized = $false
        }
        $currentForeground = & $invokeWindowAdapter 'GetForegroundWindowInfo' @{}
        $stepRecord = [ordered]@{
            cycle = $cycle
            candidate = & $toPlain $candidate
            activation = & $toPlain $activation
            foreground_window = & $toPlain $currentForeground
        }
        [void] $activationResults.Add($stepRecord)
        if (-not $activation.succeeded) {
            $activationSucceeded = $false
            break
        }

        if ($dwellMilliseconds -gt 0) {
            Start-Sleep -Milliseconds $dwellMilliseconds
        }
    }

    $restoreResult = & $invokeWindowAdapter 'ActivateWindow' @{
        handle = $foregroundHandle
        restore_if_minimized = $false
    }
    $restoredForeground = & $invokeWindowAdapter 'GetForegroundWindowInfo' @{}
    $restoredHandle = if ($null -ne $restoredForeground -and $restoredForeground.handle) { [int64] $restoredForeground.handle } else { 0 }
    $loopReturned = $restoreResult.succeeded -and $restoredHandle -eq $foregroundHandle

    $status = if ($activationSucceeded -and $loopReturned) { 'Succeeded' } else { 'Failed' }
    $message = if ($status -eq 'Succeeded') { 'Window activation cycle completed and restored the original foreground window.' } elseif (-not $activationSucceeded) { 'Window activation cycle failed while activating an Alt-Tab candidate.' } else { 'Window activation cycle completed, but the original foreground window could not be restored.' }
    $errors = @()
    if (-not $activationSucceeded) { $errors += 'WindowActivationFailed' }
    if (-not $loopReturned) { $errors += 'ForegroundRestoreFailed' }

    return & $newResult -Status $status -Message $message -Observed @{
        original_foreground_handle = $foregroundHandle
        alt_tab_candidate_count = $candidateHandles.Count
        cycle_count = @($activationResults).Count
        loop_returned = $loopReturned
    } -Outputs @{
        captured_state = @{
            foreground_window = $foregroundWindow
            windows = @($altTabCandidates)
        }
        original_foreground_window = $foregroundWindow
        alt_tab_candidates = @($altTabCandidates)
        activation_results = @($activationResults)
        restore_result = & $toPlain $restoreResult
        dwell_ms = $dwellMilliseconds
        max_cycles = $maxCycles
    } -Errors $errors
}.GetNewClosure()

$restoreForeground = {
    param(
        [System.Collections.IDictionary] $Arguments = @{},
        $ExecutionResult
    )

    $capturedState = & $getCapturedState $Arguments $ExecutionResult
    if ($null -eq $capturedState -or -not $capturedState.Contains('foreground_window') -or $null -eq $capturedState.foreground_window) {
        return & $newResult -Status 'Succeeded' -Message 'No captured foreground window was available to restore.' -Outputs @{ restored = $false }
    }

    $foregroundWindow = $capturedState.foreground_window
    if (-not ($foregroundWindow -is [System.Collections.IDictionary]) -or -not $foregroundWindow.Contains('handle')) {
        return & $newResult -Status 'Succeeded' -Message 'No captured foreground window was available to restore.' -Outputs @{ restored = $false }
    }

    $activation = & $invokeWindowAdapter 'ActivateWindow' @{
        handle = [int64] $foregroundWindow.handle
        restore_if_minimized = $true
    }

    if (-not $activation.succeeded) {
        return & $newResult -Status 'Failed' -Message 'Failed to restore the original foreground window.' -Observed (& $toPlain $activation) -Outputs @{ restored = $false } -Errors @('ForegroundRestoreFailed')
    }

    return & $newResult -Status 'Succeeded' -Message 'Restored the original foreground window.' -Observed (& $toPlain $activation.window) -Outputs @{
        restored = $true
        restored_window = & $toPlain $activation.window
    }
}.GetNewClosure()

return @{
    Domain = 'window'
    Operations = @{
        capture = {
            param($ctx, $operationArguments, $prior)

            $state = & $captureState
            & $newResult -Status 'Succeeded' -Message 'Captured window activation state.' -Observed @{
                foreground_window = $state.foreground_window
                window_count = @($state.windows).Count
            } -Outputs @{
                captured_state = @{
                    foreground_window = $state.foreground_window
                }
                windows = @($state.windows)
            }
        }.GetNewClosure()
        apply = {
            param($ctx, $operationArguments, $prior)

            & $applyCycle $operationArguments
        }.GetNewClosure()
        verify = {
            param($ctx, $operationArguments, $prior)

            $capturedState = & $getCapturedState $operationArguments $prior
            $currentForeground = & $invokeWindowAdapter 'GetForegroundWindowInfo' @{}
            if ($null -eq $capturedState -or -not $capturedState.Contains('foreground_window') -or $null -eq $capturedState.foreground_window) {
                return & $newResult -Status 'Succeeded' -Message 'No original foreground window was captured.' -Observed @{
                    foreground_window = & $toPlain $currentForeground
                } -Outputs @{
                    restored = $false
                }
            }

            $expectedHandle = [int64] $capturedState.foreground_window.handle
            $observedHandle = if ($null -ne $currentForeground -and $currentForeground.handle) { [int64] $currentForeground.handle } else { 0 }
            if ($expectedHandle -ne 0 -and $observedHandle -ne $expectedHandle) {
                return & $newResult -Status 'Failed' -Message 'Foreground window was not restored after activation cycling.' -Observed @{
                    foreground_window = & $toPlain $currentForeground
                } -Outputs @{
                    expected_handle = $expectedHandle
                    observed_handle = $observedHandle
                } -Errors @('ForegroundWindowDrift')
            }

            & $newResult -Status 'Succeeded' -Message 'Foreground window restored after activation cycling.' -Observed @{
                foreground_window = & $toPlain $currentForeground
            } -Outputs @{
                restored = $true
                foreground_window = & $toPlain $currentForeground
            }
        }.GetNewClosure()
        reset = {
            param($ctx, $operationArguments, $prior)

            & $restoreForeground $operationArguments $prior
        }.GetNewClosure()
    }
}
