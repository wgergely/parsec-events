function ConvertTo-ParsecRecipe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Document,

        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not $Document.Contains('name')) {
        throw "Recipe file '$Path' is missing a name."
    }

    $definitions = Get-ParsecRecipeIngredientDefinitions -Document $Document
    $steps = @()
    if ($Document.Contains('steps')) {
        foreach ($step in @($Document.steps)) {
            $steps += Resolve-ParsecRecipeStep -Step $step -Definitions $definitions -Path $Path
        }
    }

    return [ordered]@{
        name         = [string] $Document.name
        description  = [string] $Document.description
        initial_mode = [string] $Document.initial_mode
        target_mode  = [string] $Document.target_mode
        path         = $Path
        ingredient_definitions = $definitions
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
    $document = ConvertFrom-ParsecToml -Path $path
    return ConvertTo-ParsecRecipe -Document $document -Path $path
}

function Merge-ParsecRecipeMap {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Base = @{},

        [Parameter()]
        [System.Collections.IDictionary] $Override = @{}
    )

    $result = [ordered]@{}
    foreach ($key in @($Base.Keys)) {
        $result[$key] = ConvertTo-ParsecPlainObject -InputObject $Base[$key]
    }

    foreach ($key in @($Override.Keys)) {
        $overrideValue = ConvertTo-ParsecPlainObject -InputObject $Override[$key]
        if (
            $result.Contains($key) -and
            $result[$key] -is [System.Collections.IDictionary] -and
            $overrideValue -is [System.Collections.IDictionary]
        ) {
            $result[$key] = Merge-ParsecRecipeMap -Base $result[$key] -Override $overrideValue
        }
        else {
            $result[$key] = $overrideValue
        }
    }

    return $result
}

function Get-ParsecRecipeIngredientDefinitions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Document
    )

    if ($Document.Contains('ingredient_definitions')) {
        return ConvertTo-ParsecPlainObject -InputObject $Document.ingredient_definitions
    }

    if ($Document.Contains('ingredients')) {
        return ConvertTo-ParsecPlainObject -InputObject $Document.ingredients
    }

    return [ordered]@{}
}

function Resolve-ParsecRecipeStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Step,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Definitions,

        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not $Step.id) {
        throw "Recipe step in '$Path' is missing an id."
    }

    $definitionName = if ($Step.Contains('definition')) { [string] $Step.definition } elseif ($Step.Contains('uses')) { [string] $Step.uses } else { $null }
    $definition = if ($definitionName) {
        if (-not $Definitions.Contains($definitionName)) {
            throw "Recipe step '$($Step.id)' in '$Path' references unknown definition '$definitionName'."
        }

        ConvertTo-ParsecPlainObject -InputObject $Definitions[$definitionName]
    }
    else {
        @{}
    }

    $definitionArguments = if ($definition.Contains('arguments')) { [System.Collections.IDictionary] $definition.arguments } else { @{} }
    $stepArguments = if ($Step.Contains('arguments')) { [System.Collections.IDictionary] $Step.arguments } else { @{} }
    $resolvedArguments = Merge-ParsecRecipeMap -Base $definitionArguments -Override $stepArguments

    $resolvedDependsOn = @()
    if ($definition.Contains('depends_on')) {
        $resolvedDependsOn += @($definition.depends_on)
    }

    if ($Step.Contains('depends_on')) {
        foreach ($dependency in @($Step.depends_on)) {
            if ($resolvedDependsOn -notcontains $dependency) {
                $resolvedDependsOn += $dependency
            }
        }
    }

    $definitionCondition = if ($definition.Contains('condition')) { [System.Collections.IDictionary] $definition.condition } else { @{} }
    $stepCondition = if ($Step.Contains('condition')) { [System.Collections.IDictionary] $Step.condition } else { @{} }
    $resolvedCondition = Merge-ParsecRecipeMap -Base $definitionCondition -Override $stepCondition

    $ingredient = if ($Step.Contains('ingredient')) { [string] $Step.ingredient } elseif ($definition.Contains('ingredient')) { [string] $definition.ingredient } else { $null }
    if (-not $ingredient) {
        throw "Recipe step '$($Step.id)' in '$Path' is missing an ingredient."
    }

    return [ordered]@{
        id                  = [string] $Step.id
        definition          = $definitionName
        ingredient          = $ingredient
        operation           = if ($Step.Contains('operation')) { [string] $Step.operation } elseif ($definition.Contains('operation')) { [string] $definition.operation } else { 'apply' }
        depends_on          = @($resolvedDependsOn)
        arguments           = $resolvedArguments
        verify              = if ($Step.Contains('verify')) { [bool] $Step.verify } elseif ($definition.Contains('verify')) { [bool] $definition.verify } else { $true }
        compensation_policy = if ($Step.Contains('compensation_policy')) { [string] $Step.compensation_policy } elseif ($definition.Contains('compensation_policy')) { [string] $definition.compensation_policy } else { 'none' }
        retry_count         = if ($Step.Contains('retry_count')) { [int] $Step.retry_count } elseif ($definition.Contains('retry_count')) { [int] $definition.retry_count } else { 0 }
        retry_delay_ms      = if ($Step.Contains('retry_delay_ms')) { [int] $Step.retry_delay_ms } elseif ($definition.Contains('retry_delay_ms')) { [int] $definition.retry_delay_ms } else { 0 }
        allow_diagnostics   = if ($Step.Contains('allow_diagnostics')) { [bool] $Step.allow_diagnostics } elseif ($definition.Contains('allow_diagnostics')) { [bool] $definition.allow_diagnostics } else { $false }
        condition           = $resolvedCondition
    }
}

function Test-ParsecStepCondition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Step,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $RunState
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
        [System.Collections.IDictionary] $RunState,

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
        [System.Collections.IDictionary] $RunState
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
        [System.Collections.IDictionary] $RunState,

        [Parameter(Mandatory)]
        [string] $StateRoot
    )

    foreach ($dependency in @($Step.depends_on)) {
        $dependencyResult = Get-ParsecStepResultById -RunState $RunState -StepId $dependency
        if ($null -eq $dependencyResult -or -not (Test-ParsecSuccessfulStatus -Status $dependencyResult.status)) {
            return [ordered]@{
                step_id             = $Step.id
                ingredient          = $Step.ingredient
                operation           = $Step.operation
                status              = 'Blocked'
                operation_result    = $null
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
            operation           = $Step.operation
            status              = 'Skipped'
            operation_result    = $null
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
    $operationResult = $null
    do {
        $attempt++
        $operationResult = Invoke-ParsecIngredientOperation -Name $Step.ingredient -Operation $Step.operation -Arguments $Step.arguments -StateRoot $StateRoot -RunState $RunState
        if ((Test-ParsecSuccessfulStatus -Status $operationResult.Status) -or $attempt -gt $Step.retry_count) {
            break
        }

        if ($Step.retry_delay_ms -gt 0) {
            Start-Sleep -Milliseconds $Step.retry_delay_ms
        }
    }
    while ($true)

    $verificationResult = $null
    $finalStatus = $operationResult.Status
    $definition = Get-ParsecIngredientDefinition -Name $Step.ingredient
    $operationOutputs = ConvertTo-ParsecPlainObject -InputObject $operationResult.Outputs
    if ($operationOutputs -is [System.Collections.IDictionary] -and $operationOutputs.Contains('snapshot_name') -and $operationOutputs['snapshot_name']) {
        $RunState.active_snapshot = [string] $operationOutputs['snapshot_name']
    }

    if ($Step.verify -and (Test-ParsecSuccessfulStatus -Status $operationResult.Status) -and (Test-ParsecIngredientOperationSupported -Definition $definition -Operation 'verify')) {
        $verificationResult = Invoke-ParsecIngredientOperation -Name $Step.ingredient -Operation 'verify' -Arguments $Step.arguments -ExecutionResult $operationResult -StateRoot $StateRoot -RunState $RunState
        if ($null -ne $verificationResult -and -not (Test-ParsecSuccessfulStatus -Status $verificationResult.Status)) {
            $finalStatus = if ($verificationResult.Status -eq 'Ambiguous') { 'Ambiguous' } else { 'SucceededWithDrift' }
        }
    }

    $compensationResult = $null
    if (($finalStatus -eq 'Failed' -or $finalStatus -eq 'Ambiguous') -and $Step.compensation_policy -eq 'explicit' -and (Test-ParsecIngredientOperationSupported -Definition $definition -Operation 'reset')) {
        $compensationResult = Invoke-ParsecIngredientOperation -Name $Step.ingredient -Operation 'reset' -Arguments $Step.arguments -ExecutionResult $operationResult -StateRoot $StateRoot -RunState $RunState
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
        operation           = $Step.operation
        status              = $finalStatus
        operation_result    = $operationResult
        execution_result    = $operationResult
        verification_result = $verificationResult
        compensation_result = $compensationResult
        started_at          = [DateTimeOffset]::UtcNow.ToString('o')
        completed_at        = [DateTimeOffset]::UtcNow.ToString('o')
        message             = if ($null -ne $verificationResult -and $verificationResult.Message) { $verificationResult.Message } else { $operationResult.Message }
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
    $runState.active_snapshot = $executorState.active_snapshot
    Save-ParsecExecutorStateDocument -StateDocument $executorState -StateRoot $stateRoot | Out-Null
    Write-ParsecEventRecord -EventType 'executor-run-started' -Payload @{
        run_id          = $runState.run_id
        transition_id   = $runState.transition_id
        recipe_name     = $Recipe.name
        desired_state   = $Recipe.target_mode
        active_snapshot = $runState.active_snapshot
    } -StateRoot $stateRoot | Out-Null

    foreach ($step in @($Recipe.steps)) {
        $runState.transition_phase = "Executing:$($step.id)"
        $stepResult = Invoke-ParsecStep -Step $step -RunState $runState -StateRoot $stateRoot
        $runState.step_results += $stepResult
        if ($null -ne $stepResult.operation_result) {
            $stepOutputs = ConvertTo-ParsecPlainObject -InputObject $stepResult.operation_result.Outputs
            if ($stepOutputs -is [System.Collections.IDictionary] -and $stepOutputs.Contains('snapshot_name') -and $stepOutputs['snapshot_name']) {
                $runState.active_snapshot = [string] $stepOutputs['snapshot_name']
            }
        }

        if ($RunState.active_snapshot) {
            $executorState.active_snapshot = $RunState.active_snapshot
            Save-ParsecExecutorStateDocument -StateDocument $executorState -StateRoot $stateRoot | Out-Null
        }

        Write-ParsecEventRecord -EventType 'executor-step-completed' -Payload @{
            run_id          = $runState.run_id
            transition_id   = $runState.transition_id
            step_id         = $step.id
            ingredient      = $step.ingredient
            operation       = $step.operation
            status          = $stepResult.status
            active_snapshot = $runState.active_snapshot
        } -StateRoot $stateRoot | Out-Null

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

    $executorState.active_snapshot = $runState.active_snapshot
    $executorState.transition_phase = 'Idle'
    $executorState.last_error = if (@($runState.errors).Count -gt 0) { $runState.errors[-1] } else { $null }
    Save-ParsecExecutorStateDocument -StateDocument $executorState -StateRoot $stateRoot | Out-Null
    Write-ParsecEventRecord -EventType 'executor-run-completed' -Payload @{
        run_id            = $runState.run_id
        transition_id     = $runState.transition_id
        recipe_name       = $Recipe.name
        terminal_status   = $runState.terminal_status
        actual_state      = $runState.actual_state
        last_good_state   = $runState.last_good_state
        active_snapshot   = $runState.active_snapshot
        transition_phase  = $runState.transition_phase
        error_count       = @($runState.errors).Count
        warning_count     = @($runState.warnings).Count
    } -StateRoot $stateRoot | Out-Null

    return $runState
}
