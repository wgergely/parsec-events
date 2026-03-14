$supportFiles = @(
    (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Core\HostSupport.ps1'),
    (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Utility.ps1')
)

foreach ($file in @($supportFiles)) { . $file }

$toPlain = {
    param($InputObject)

    if (Get-Command -Name 'ConvertTo-ParsecPlainObject' -ErrorAction SilentlyContinue) {
        return ConvertTo-ParsecPlainObject -InputObject $InputObject
    }

    return $InputObject
}.GetNewClosure()

$newResult = {
    param(
        [string] $Status,
        [string] $Message = '',
        [System.Collections.IDictionary] $Requested = @{},
        [System.Collections.IDictionary] $Observed = @{},
        [System.Collections.IDictionary] $Outputs = @{},
        [string[]] $Warnings = @(),
        [string[]] $Errors = @(),
        [bool] $CanCompensate = $false
    )

    if (Get-Command -Name 'New-ParsecResult' -ErrorAction SilentlyContinue) {
        return New-ParsecResult -Status $Status -Message $Message -Requested $Requested -Observed $Observed -Outputs $Outputs -Warnings $Warnings -Errors $Errors -CanCompensate $CanCompensate
    }

    return [pscustomobject]@{
        PSTypeName = 'ParsecEventExecutor.Result'
        Status = $Status
        Message = $Message
        Requested = & $toPlain $Requested
        Observed = & $toPlain $Observed
        Outputs = & $toPlain $Outputs
        Warnings = @($Warnings)
        Errors = @($Errors)
        CanCompensate = $CanCompensate
        Timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    }
}.GetNewClosure()

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
            return & $toPlain ([ParsecEventExecutor.DisplayNative]::GetForegroundWindowCapture())
        }
        'GetTopLevelWindows' {
            return @([ParsecEventExecutor.DisplayNative]::GetTopLevelWindows()) | ForEach-Object { & $toPlain $_ }
        }
        'ActivateWindow' {
            $handle = [int64] $Arguments.handle
            $succeeded = [bool] [ParsecEventExecutor.DisplayNative]::ActivateWindow($handle, [bool] $Arguments.restore_if_minimized)
            $window = & $toPlain ([ParsecEventExecutor.DisplayNative]::GetForegroundWindowCapture())
            return [ordered]@{
                succeeded = $succeeded
                handle = $handle
                window = $window
            }
        }
        default {
            throw "Window adapter method '$Method' is not available."
        }
    }
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
            if ($null -eq $window.handle -or [int64] $window.handle -eq 0) { continue }
            if ($window.Contains('is_shell_window') -and [bool] $window.is_shell_window) { continue }
            if ($window.Contains('is_visible') -and -not [bool] $window.is_visible) { continue }
            if ($window.Contains('is_cloaked') -and [bool] $window.is_cloaked) { continue }
            if ($window.Contains('is_on_input_desktop') -and -not [bool] $window.is_on_input_desktop) { continue }
            if ($window.Contains('is_on_current_virtual_desktop') -and -not [bool] $window.is_on_current_virtual_desktop) { continue }
            if ($window.Contains('is_minimized') -and [bool] $window.is_minimized) { continue }

            $title = if ($window.Contains('title')) { [string] $window.title } else { '' }
            if ([string]::IsNullOrWhiteSpace($title)) { continue }

            $className = if ($window.Contains('class_name')) { [string] $window.class_name } else { '' }
            if ($className -in @('IME', 'tooltips_class32', 'SysShadow', 'ForegroundStaging', 'ThumbnailDeviceHelperWnd', 'PseudoConsoleWindow')) { continue }

            $processName = if ($window.Contains('process_name')) { [string] $window.process_name } else { '' }
            if ($processName -eq 'ApplicationFrameHost') { continue }
            if ($title -eq 'Windows Input Experience' -or $processName -eq 'TextInputHost') { continue }

            $extendedStyle = if ($window.Contains('extended_style') -and $null -ne $window.extended_style) { [int64] $window.extended_style } else { 0 }
            $ownerHandle = if ($window.Contains('owner_handle') -and $null -ne $window.owner_handle) { [int64] $window.owner_handle } else { 0 }
            $hasAppWindowStyle = ($extendedStyle -band 0x40000) -ne 0
            $hasToolWindowStyle = ($extendedStyle -band 0x80) -ne 0
            $hasNoActivateStyle = ($extendedStyle -band 0x08000000) -ne 0
            $hasTopMostStyle = ($extendedStyle -band 0x8) -ne 0

            $width = if ($window.Contains('width') -and $null -ne $window.width) { [int] $window.width } else { 0 }
            $height = if ($window.Contains('height') -and $null -ne $window.height) { [int] $window.height } else { 0 }
            if ($width -gt 0 -and $height -gt 0 -and ($width -lt 64 -or $height -lt 64)) { continue }
            if (($extendedStyle -band 0x80) -ne 0) { continue }
            if ($hasNoActivateStyle) { continue }
            if ($ownerHandle -ne 0 -and -not $hasAppWindowStyle) { continue }
            if ($hasToolWindowStyle) { continue }
            if ($hasTopMostStyle) { continue }

            & $toPlain $window
        }
    )

    return [ordered]@{
        captured_at = [DateTimeOffset]::UtcNow.ToString('o')
        foreground_window = & $toPlain $foreground
        windows = @($candidates | ForEach-Object { & $toPlain $_ })
    }
}.GetNewClosure()

$cycleActivation = {
    param(
        [System.Collections.IDictionary] $Arguments = @{}
    )

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
        $Prior
    )

    $capturedState = if ($Arguments.Contains('captured_state') -and $Arguments.captured_state -is [System.Collections.IDictionary]) {
        & $toPlain $Arguments.captured_state
    }
    elseif ($null -ne $Prior -and $Prior.Outputs -and $Prior.Outputs.captured_state) {
        & $toPlain $Prior.Outputs.captured_state
    }
    else {
        $null
    }
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
    Name = 'window'
    Api = [pscustomobject]@{
        Invoke = {
            param(
                [string] $Method,
                [System.Collections.IDictionary] $Arguments = @{},
                $Prior,
                [string] $StateRoot = (Get-ParsecDefaultStateRoot),
                [System.Collections.IDictionary] $RunState = @{}
            )

            # StateRoot, RunState required by domain Invoke contract
            $null = $StateRoot
            $null = $RunState

            switch ($Method) {
                'CaptureState' { return & $captureState }
                'CycleActivation' { return & $cycleActivation $Arguments }
                'RestoreForeground' { return & $restoreForeground $Arguments $Prior }
                default { throw "Window domain method '$Method' is not available." }
            }
        }.GetNewClosure()
    }
}
