function ConvertTo-ParsecRecipe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Document,

        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not $Document.Contains('name')) {
        throw "Recipe file '$Path' is missing a name."
    }

    $steps = @()
    if ($Document.Contains('steps')) {
        foreach ($step in @($Document.steps)) {
            if (-not $step.id) {
                throw "Recipe step in '$Path' is missing an id."
            }

            if (-not $step.ingredient) {
                throw "Recipe step '$($step.id)' in '$Path' is missing an ingredient."
            }

            $steps += [ordered]@{
                id                  = [string] $step.id
                ingredient          = [string] $step.ingredient
                depends_on          = @($step.depends_on)
                arguments           = if ($step.Contains('arguments')) { [hashtable] $step.arguments } else { @{} }
                verify              = if ($step.Contains('verify')) { [bool] $step.verify } else { $true }
                compensation_policy = if ($step.Contains('compensation_policy')) { [string] $step.compensation_policy } else { 'none' }
                retry_count         = if ($step.Contains('retry_count')) { [int] $step.retry_count } else { 0 }
                retry_delay_ms      = if ($step.Contains('retry_delay_ms')) { [int] $step.retry_delay_ms } else { 0 }
                allow_diagnostics   = if ($step.Contains('allow_diagnostics')) { [bool] $step.allow_diagnostics } else { $false }
                condition           = if ($step.Contains('condition')) { [hashtable] $step.condition } else { @{} }
            }
        }
    }

    return [ordered]@{
        name         = [string] $Document.name
        description  = [string] $Document.description
        initial_mode = [string] $Document.initial_mode
        target_mode  = [string] $Document.target_mode
        path         = $Path
        steps        = @($steps)
    }
}

function Get-ParsecRecipeDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $NameOrPath
    )

    $path = Resolve-ParsecRecipePath -NameOrPath $NameOrPath
    $document = [ordered]@{}
    $steps = New-Object System.Collections.Generic.List[hashtable]
    $currentStep = $null
    $inStepArguments = $false

    foreach ($rawLine in (Get-Content -LiteralPath $path)) {
        $line = Remove-ParsecTomlComment -Line $rawLine
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -eq '[[steps]]') {
            if ($null -ne $currentStep) {
                $steps.Add($currentStep)
            }

            $currentStep = [ordered]@{
                depends_on = @()
                arguments  = @{}
            }
            $inStepArguments = $false
            continue
        }

        if ($line -eq '[steps.arguments]') {
            $inStepArguments = $true
            continue
        }

        if ($line -match '^\[.+\]$') {
            $inStepArguments = $false
            continue
        }

        if ($line -notmatch '^([A-Za-z0-9_\-]+)\s*=\s*(.+)$') {
            throw "Unsupported recipe line: $line"
        }

        $key = $Matches[1]
        $value = ConvertFrom-ParsecTomlValue -Value $Matches[2]
        if ($null -ne $currentStep) {
            if ($inStepArguments) {
                $currentStep.arguments[$key] = $value
            }
            else {
                $currentStep[$key] = $value
            }
        }
        else {
            $document[$key] = $value
        }
    }

    if ($null -ne $currentStep) {
        $steps.Add($currentStep)
    }

    $document.steps = @($steps)
    return ConvertTo-ParsecRecipe -Document $document -Path $path
}

function Test-ParsecStepCondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Step,

        [Parameter(Mandatory)]
        [hashtable] $RunState
    )

    if (-not $Step.condition -or $Step.condition.Count -eq 0) {
        return $true
    }

    if ($Step.condition.Contains('mode_is')) {
        return $RunState.actual_state -eq $Step.condition.mode_is -or $RunState.desired_state -eq $Step.condition.mode_is
    }

    return $true
}

function Get-ParsecStepResultById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $RunState,

        [Parameter(Mandatory)]
        [string] $StepId
    )

    foreach ($stepResult in @($RunState.step_results)) {
        if ($stepResult.step_id -eq $StepId) {
            return $stepResult
        }
    }

    return $null
}

function Resolve-ParsecRunTerminalStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $RunState
    )

    $stepResults = @($RunState.step_results)
    if ($stepResults.Count -eq 0) {
        return 'Failed'
    }

    if (@($RunState.compensation_logs).Count -gt 0 -and ($stepResults.Status -contains 'Failed')) {
        return 'Compensated'
    }

    if ($stepResults.Status -contains 'Ambiguous') {
        return 'Ambiguous'
    }

    if ($stepResults.Status -contains 'Failed') {
        if ($stepResults.Status -contains 'Succeeded') {
            return 'PartiallyApplied'
        }

        return 'Failed'
    }

    if ($stepResults.Status -contains 'SucceededWithDrift') {
        return 'SucceededWithDrift'
    }

    return 'Succeeded'
}

function Invoke-ParsecStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Step,

        [Parameter(Mandatory)]
        [hashtable] $RunState,

        [Parameter(Mandatory)]
        [string] $StateRoot
    )

    foreach ($dependency in @($Step.depends_on)) {
        $dependencyResult = Get-ParsecStepResultById -RunState $RunState -StepId $dependency
        if ($null -eq $dependencyResult -or -not (Test-ParsecSuccessfulStatus -Status $dependencyResult.status)) {
            return [ordered]@{
                step_id             = $Step.id
                ingredient          = $Step.ingredient
                status              = 'Blocked'
                execution_result    = $null
                verification_result = $null
                compensation_result = $null
                started_at          = [DateTimeOffset]::UtcNow.ToString('o')
                completed_at        = [DateTimeOffset]::UtcNow.ToString('o')
                message             = "Blocked by dependency '$dependency'."
                requested_arguments = ConvertTo-ParsecPlainObject -InputObject $Step.arguments
            }
        }
    }

    if (-not (Test-ParsecStepCondition -Step $Step -RunState $RunState)) {
        return [ordered]@{
            step_id             = $Step.id
            ingredient          = $Step.ingredient
            status              = 'Skipped'
            execution_result    = $null
            verification_result = $null
            compensation_result = $null
            started_at          = [DateTimeOffset]::UtcNow.ToString('o')
            completed_at        = [DateTimeOffset]::UtcNow.ToString('o')
            message             = 'Step condition evaluated to false.'
            requested_arguments = ConvertTo-ParsecPlainObject -InputObject $Step.arguments
        }
    }

    $attempt = 0
    $executionResult = $null
    do {
        $attempt++
        $executionResult = Invoke-ParsecIngredientExecute -Name $Step.ingredient -Arguments $Step.arguments -StateRoot $StateRoot -RunState $RunState
        if ((Test-ParsecSuccessfulStatus -Status $executionResult.Status) -or $attempt -gt $Step.retry_count) {
            break
        }

        if ($Step.retry_delay_ms -gt 0) {
            Start-Sleep -Milliseconds $Step.retry_delay_ms
        }
    }
    while ($true)

    $verificationResult = $null
    $finalStatus = $executionResult.Status
    if ($Step.verify -and (Test-ParsecSuccessfulStatus -Status $executionResult.Status)) {
        $verificationResult = Invoke-ParsecIngredientVerify -Name $Step.ingredient -Arguments $Step.arguments -ExecutionResult $executionResult -StateRoot $StateRoot -RunState $RunState
        if ($null -ne $verificationResult -and -not (Test-ParsecSuccessfulStatus -Status $verificationResult.Status)) {
            $finalStatus = if ($verificationResult.Status -eq 'Ambiguous') { 'Ambiguous' } else { 'SucceededWithDrift' }
        }
    }

    $compensationResult = $null
    if (($finalStatus -eq 'Failed' -or $finalStatus -eq 'Ambiguous') -and $Step.compensation_policy -eq 'explicit') {
        $compensationResult = Invoke-ParsecIngredientCompensate -Name $Step.ingredient -Arguments $Step.arguments -ExecutionResult $executionResult -StateRoot $StateRoot -RunState $RunState
        if ($null -ne $compensationResult) {
            $RunState.compensation_logs += $compensationResult
            if (Test-ParsecSuccessfulStatus -Status $compensationResult.Status) {
                $finalStatus = 'Compensated'
            }
        }
    }

    return [ordered]@{
        step_id             = $Step.id
        ingredient          = $Step.ingredient
        status              = $finalStatus
        execution_result    = $executionResult
        verification_result = $verificationResult
        compensation_result = $compensationResult
        started_at          = [DateTimeOffset]::UtcNow.ToString('o')
        completed_at        = [DateTimeOffset]::UtcNow.ToString('o')
        message             = if ($null -ne $verificationResult -and $verificationResult.Message) { $verificationResult.Message } else { $executionResult.Message }
        requested_arguments = ConvertTo-ParsecPlainObject -InputObject $Step.arguments
    }
}

function Invoke-ParsecRecipeInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Recipe,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $stateRoot = Initialize-ParsecStateRoot -StateRoot $StateRoot
    $runState = New-ParsecRunState -Recipe $Recipe -StateRoot $stateRoot
    $executorState = Get-ParsecExecutorStateDocument -StateRoot $stateRoot
    $executorState.desired_mode = $Recipe.target_mode
    $executorState.transition_id = $runState.transition_id
    $executorState.transition_phase = 'Running'
    $executorState.last_run_id = $runState.run_id
    Save-ParsecExecutorStateDocument -StateDocument $executorState -StateRoot $stateRoot | Out-Null

    foreach ($step in @($Recipe.steps)) {
        $runState.transition_phase = "Executing:$($step.id)"
        $stepResult = Invoke-ParsecStep -Step $step -RunState $runState -StateRoot $stateRoot
        $runState.step_results += $stepResult

        if ($stepResult.status -eq 'Failed' -or $stepResult.status -eq 'Ambiguous') {
            $runState.errors += $stepResult.message
        }

        if ($stepResult.status -eq 'SucceededWithDrift') {
            $runState.warnings += $stepResult.message
        }
    }

    $runState.terminal_status = Resolve-ParsecRunTerminalStatus -RunState $runState
    $runState.transition_phase = 'Completed'
    $runState.actual_state = if (Test-ParsecSuccessfulStatus -Status $runState.terminal_status) { $Recipe.target_mode } else { $executorState.actual_mode }
    $runState.last_good_state = if (Test-ParsecSuccessfulStatus -Status $runState.terminal_status) { $Recipe.target_mode } else { $executorState.last_good_mode }
    $runState.completed_at = [DateTimeOffset]::UtcNow.ToString('o')
    Save-ParsecRunState -RunState $runState | Out-Null

    $executorState.actual_mode = $runState.actual_state
    if ($runState.last_good_state) {
        $executorState.last_good_mode = $runState.last_good_state
    }

    $executorState.transition_phase = 'Idle'
    $executorState.last_error = if (@($runState.errors).Count -gt 0) { $runState.errors[-1] } else { $null }
    Save-ParsecExecutorStateDocument -StateDocument $executorState -StateRoot $stateRoot | Out-Null

    return $runState
}
