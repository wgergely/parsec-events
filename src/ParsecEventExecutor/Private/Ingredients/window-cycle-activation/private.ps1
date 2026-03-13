function Get-ParsecWindowCaptureState {
    [CmdletBinding()]
    param()

    $foreground = $null
    foreach ($attempt in 1..5) {
        $foreground = Invoke-ParsecWindowAdapter -Method 'GetForegroundWindowInfo'
        if ($null -ne $foreground -and $foreground.handle) {
            break
        }

        Start-Sleep -Milliseconds 100
    }

    $windows = @(Get-ParsecAltTabCandidateWindows)

    return [ordered]@{
        captured_at = [DateTimeOffset]::UtcNow.ToString('o')
        foreground_window = ConvertTo-ParsecPlainObject -InputObject $foreground
        windows = @($windows | ForEach-Object { ConvertTo-ParsecPlainObject -InputObject $_ })
    }
}

function Test-ParsecWindowActivationCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Window,

        [Parameter()]
        [bool] $IncludeMinimized = $false
    )

    if ($null -eq $Window.handle -or [int64] $Window.handle -eq 0) { return $false }
    if ($Window.Contains('is_shell_window') -and [bool] $Window.is_shell_window) { return $false }
    if ($Window.Contains('is_visible') -and -not [bool] $Window.is_visible) { return $false }
    if ($Window.Contains('is_cloaked') -and [bool] $Window.is_cloaked) { return $false }
    if ($Window.Contains('is_on_input_desktop') -and -not [bool] $Window.is_on_input_desktop) { return $false }
    if ($Window.Contains('is_on_current_virtual_desktop') -and -not [bool] $Window.is_on_current_virtual_desktop) { return $false }
    if (-not $IncludeMinimized -and $Window.Contains('is_minimized') -and [bool] $Window.is_minimized) { return $false }

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
}

function Get-ParsecAltTabCandidateWindows {
    [CmdletBinding()]
    param(
        [Parameter()]
        [bool] $IncludeMinimized = $false
    )

    $windows = @(Invoke-ParsecWindowAdapter -Method 'GetTopLevelWindows')
    return @(
        foreach ($window in $windows) {
            if (Test-ParsecWindowActivationCandidate -Window $window -IncludeMinimized:$IncludeMinimized) {
                ConvertTo-ParsecPlainObject -InputObject $window
            }
        }
    )
}

function Invoke-ParsecWindowCycleInternal {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{}
    )

    $dwellMilliseconds = if ($Arguments.ContainsKey('dwell_ms')) { [int] $Arguments.dwell_ms } else { 100 }
    if ($dwellMilliseconds -lt 0) { throw 'dwell_ms must be zero or greater.' }

    $maxCycles = if ($Arguments.ContainsKey('max_cycles')) { [int] $Arguments.max_cycles } else { 30 }
    if ($maxCycles -lt 1) { throw 'max_cycles must be one or greater.' }

    $captureState = Get-ParsecWindowCaptureState
    $foregroundWindow = if ($captureState.Contains('foreground_window')) { ConvertTo-ParsecPlainObject -InputObject $captureState.foreground_window } else { $null }
    $foregroundHandle = if ($foregroundWindow -is [System.Collections.IDictionary] -and $foregroundWindow.Contains('handle') -and $null -ne $foregroundWindow.handle) { [int64] $foregroundWindow.handle } else { 0 }
    if ($foregroundHandle -eq 0) {
        return New-ParsecResult -Status 'Failed' -Message 'Could not capture the current foreground window.' -Errors @('MissingForegroundWindow')
    }

    $altTabCandidates = if ($captureState.Contains('windows')) { @($captureState.windows) } else { @() }
    $candidateHandles = @($altTabCandidates | ForEach-Object { if ($_ -is [System.Collections.IDictionary] -and $_.Contains('handle')) { [int64] $_.handle } })
    if ($candidateHandles.Count -eq 0) {
        return New-ParsecResult -Status 'Failed' -Message 'No Alt-Tab candidate windows were available to cycle.' -Observed @{ foreground_window = $foregroundWindow } -Errors @('MissingAltTabCandidates')
    }

    if (-not ($candidateHandles -contains $foregroundHandle)) {
        return New-ParsecResult -Status 'Failed' -Message 'The current foreground window is not an Alt-Tab candidate.' -Observed @{
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
        $activation = Invoke-ParsecWindowAdapter -Method 'ActivateWindow' -Arguments @{
            handle = [int64] $candidate.handle
            restore_if_minimized = $false
        }
        $currentForeground = Invoke-ParsecWindowAdapter -Method 'GetForegroundWindowInfo'
        $stepRecord = [ordered]@{
            cycle = $cycle
            candidate = ConvertTo-ParsecPlainObject -InputObject $candidate
            activation = ConvertTo-ParsecPlainObject -InputObject $activation
            foreground_window = ConvertTo-ParsecPlainObject -InputObject $currentForeground
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

    $restoreResult = Invoke-ParsecWindowAdapter -Method 'ActivateWindow' -Arguments @{
        handle = $foregroundHandle
        restore_if_minimized = $false
    }
    $restoredForeground = Invoke-ParsecWindowAdapter -Method 'GetForegroundWindowInfo'
    $restoredHandle = if ($null -ne $restoredForeground -and $restoredForeground.handle) { [int64] $restoredForeground.handle } else { 0 }
    $loopReturned = $restoreResult.succeeded -and $restoredHandle -eq $foregroundHandle

    $status = if ($activationSucceeded -and $loopReturned) { 'Succeeded' } else { 'Failed' }
    $message = if ($status -eq 'Succeeded') { 'Window activation cycle completed and restored the original foreground window.' } elseif (-not $activationSucceeded) { 'Window activation cycle failed while activating an Alt-Tab candidate.' } else { 'Window activation cycle completed, but the original foreground window could not be restored.' }
    $errors = @()
    if (-not $activationSucceeded) { $errors += 'WindowActivationFailed' }
    if (-not $loopReturned) { $errors += 'ForegroundRestoreFailed' }

    return New-ParsecResult -Status $status -Message $message -Observed @{
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
        restore_result = ConvertTo-ParsecPlainObject -InputObject $restoreResult
        dwell_ms = $dwellMilliseconds
        max_cycles = $maxCycles
    } -Errors $errors
}

function Restore-ParsecWindowForegroundInternal {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -eq $capturedState -or -not $capturedState.Contains('foreground_window') -or $null -eq $capturedState.foreground_window) {
        return New-ParsecResult -Status 'Succeeded' -Message 'No captured foreground window was available to restore.' -Outputs @{ restored = $false }
    }

    $foregroundWindow = $capturedState.foreground_window
    if (-not ($foregroundWindow -is [System.Collections.IDictionary]) -or -not $foregroundWindow.Contains('handle')) {
        return New-ParsecResult -Status 'Succeeded' -Message 'No captured foreground window was available to restore.' -Outputs @{ restored = $false }
    }

    $activation = Invoke-ParsecWindowAdapter -Method 'ActivateWindow' -Arguments @{
        handle = [int64] $foregroundWindow.handle
        restore_if_minimized = $true
    }

    if (-not $activation.succeeded) {
        return New-ParsecResult -Status 'Failed' -Message 'Failed to restore the original foreground window.' -Observed (ConvertTo-ParsecPlainObject -InputObject $activation) -Outputs @{ restored = $false } -Errors @('ForegroundRestoreFailed')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Restored the original foreground window.' -Observed (ConvertTo-ParsecPlainObject -InputObject $activation.window) -Outputs @{
        restored = $true
        restored_window = ConvertTo-ParsecPlainObject -InputObject $activation.window
    }
}
