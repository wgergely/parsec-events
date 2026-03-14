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
        $sequence = 0
        foreach ($step in @($Document.steps)) {
            $steps += Resolve-ParsecRecipeStep -Step $step -Definitions $definitions -Path $Path -Sequence $sequence
            $sequence++
        }
    }

    return [ordered]@{
        name = [string] $Document.name
        description = if ($Document.Contains('description')) { [string] $Document.description } else { '' }
        initial_mode = if ($Document.Contains('initial_mode')) { [string] $Document.initial_mode } else { $null }
        target_mode = if ($Document.Contains('target_mode')) { [string] $Document.target_mode } else { $null }
        path = $Path
        ingredient_definitions = $definitions
        steps = @($steps)
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
        [string] $Path,
        [Parameter()]
        [int] $Sequence = 0
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
        sequence = $Sequence
        id = [string] $Step.id
        definition = $definitionName
        ingredient = $ingredient
        operation = if ($Step.Contains('operation')) { [string] $Step.operation } elseif ($definition.Contains('operation')) { [string] $definition.operation } else { 'apply' }
        depends_on = @($resolvedDependsOn)
        arguments = $resolvedArguments
        verify = if ($Step.Contains('verify')) { [bool] $Step.verify } elseif ($definition.Contains('verify')) { [bool] $definition.verify } else { $true }
        compensation_policy = if ($Step.Contains('compensation_policy')) { [string] $Step.compensation_policy } elseif ($definition.Contains('compensation_policy')) { [string] $definition.compensation_policy } else { 'none' }
        retry_count = if ($Step.Contains('retry_count')) { [int] $Step.retry_count } elseif ($definition.Contains('retry_count')) { [int] $definition.retry_count } else { 0 }
        retry_delay_ms = if ($Step.Contains('retry_delay_ms')) { [int] $Step.retry_delay_ms } elseif ($definition.Contains('retry_delay_ms')) { [int] $definition.retry_delay_ms } else { 0 }
        allow_diagnostics = if ($Step.Contains('allow_diagnostics')) { [bool] $Step.allow_diagnostics } elseif ($definition.Contains('allow_diagnostics')) { [bool] $definition.allow_diagnostics } else { $false }
        condition = $resolvedCondition
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

function New-ParsecBlockedStepResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Step,

        [Parameter(Mandatory)]
        [string] $Message
    )

    return [ordered]@{
        step_id = $Step.id
        ingredient = $Step.ingredient
        operation = $Step.operation
        status = 'Blocked'
        operation_result = $null
        execution_result = $null
        readiness_result = $null
        verification_result = $null
        compensation_result = $null
        started_at = [DateTimeOffset]::UtcNow.ToString('o')
        completed_at = [DateTimeOffset]::UtcNow.ToString('o')
        message = $Message
        requested_arguments = ConvertTo-ParsecPlainObject -InputObject $Step.arguments
    }
}

function New-ParsecBlockedSequenceStepResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Step,

        [Parameter(Mandatory)]
        [string] $Message
    )

    return [ordered]@{
        step_id = $Step.id
        ingredient = $Step.ingredient
        operation = $Step.operation
        status = 'Blocked'
        invocation_id = $null
        token_id = $null
        token_path = $null
        capture_result = $null
        operation_result = $null
        execution_result = $null
        readiness_result = $null
        verification_result = $null
        compensation_result = $null
        started_at = [DateTimeOffset]::UtcNow.ToString('o')
        completed_at = [DateTimeOffset]::UtcNow.ToString('o')
        message = $Message
        requested_arguments = ConvertTo-ParsecPlainObject -InputObject $Step.arguments
    }
}

function Resolve-ParsecRecipeExecutionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Recipe
    )

    $steps = @($Recipe.steps)
    $validationErrors = @()
    $stepMap = @{}
    $incomingCounts = @{}
    $dependents = @{}

    foreach ($step in $steps) {
        if ($stepMap.ContainsKey($step.id)) {
            $validationErrors += "Recipe '$($Recipe.name)' contains duplicate step id '$($step.id)'."
            continue
        }

        $stepMap[$step.id] = $step
        $incomingCounts[$step.id] = 0
        $dependents[$step.id] = New-Object System.Collections.Generic.List[string]
    }

    foreach ($step in $steps) {
        if (-not $stepMap.ContainsKey($step.id)) {
            continue
        }

        foreach ($dependency in @($step.depends_on)) {
            if ($dependency -eq $step.id) {
                $validationErrors += "Recipe '$($Recipe.name)' step '$($step.id)' cannot depend on itself."
                continue
            }

            if (-not $stepMap.ContainsKey($dependency)) {
                $validationErrors += "Recipe '$($Recipe.name)' step '$($step.id)' depends on unknown step '$dependency'."
                continue
            }

            $incomingCounts[$step.id] = [int] $incomingCounts[$step.id] + 1
            $dependents[$dependency].Add($step.id) | Out-Null
        }
    }

    if ($validationErrors.Count -gt 0) {
        return [ordered]@{
            valid = $false
            errors = @($validationErrors)
            ordered_steps = @()
        }
    }

    $ready = @()
    foreach ($step in ($steps | Sort-Object sequence, id)) {
        if ([int] $incomingCounts[$step.id] -eq 0) {
            $ready += , $step
        }
    }

    $orderedSteps = @()
    while ($ready.Count -gt 0) {
        $sortedReady = @($ready | Sort-Object sequence, id)
        $next = $sortedReady[0]
        $ready = @($sortedReady | Select-Object -Skip 1)
        $orderedSteps += , $next

        foreach ($dependentId in @($dependents[$next.id])) {
            $incomingCounts[$dependentId] = [int] $incomingCounts[$dependentId] - 1
            if ([int] $incomingCounts[$dependentId] -eq 0) {
                $ready += , $stepMap[$dependentId]
            }
        }
    }

    if ($orderedSteps.Count -ne $steps.Count) {
        $validationErrors += "Recipe '$($Recipe.name)' contains a dependency cycle."
    }

    return [ordered]@{
        valid = ($validationErrors.Count -eq 0)
        errors = @($validationErrors)
        ordered_steps = @($orderedSteps)
    }
}

function Resolve-ParsecRollbackStatus {
    [CmdletBinding()]
    param(
        [Parameter()]
        [object[]] $RollbackResults = @()
    )

    $results = @($RollbackResults)
    if ($results.Count -eq 0) {
        return 'NotNeeded'
    }

    $successful = @($results | Where-Object { Test-ParsecSuccessfulStatus -Status $_.status }).Count
    if ($successful -eq $results.Count) {
        return 'Succeeded'
    }

    if ($successful -gt 0) {
        return 'Partial'
    }

    return 'Failed'
}

function Test-ParsecStepResultRollbackEligible {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $StepResult
    )

    return $StepResult.status -in @('Succeeded', 'SucceededWithDrift')
}

function Invoke-ParsecRunStateRollback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $RunState,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $FailedStepResult,

        [Parameter(Mandatory)]
        [object[]] $ExecutedSteps,

        [Parameter(Mandatory)]
        [string] $StateRoot
    )

    $rollbackResults = @()
    $rollbackCandidates = @()
    foreach ($step in @($ExecutedSteps | Sort-Object sequence -Descending)) {
        $stepResult = Get-ParsecStepResultById -RunState $RunState -StepId $step.id
        if ($null -eq $stepResult) {
            continue
        }

        if ($stepResult.step_id -eq $FailedStepResult.step_id) {
            continue
        }

        if (-not (Test-ParsecStepResultRollbackEligible -StepResult $stepResult)) {
            continue
        }

        if ($step.compensation_policy -ne 'explicit') {
            continue
        }

        $definition = Get-ParsecCoreIngredientDefinition -Name $step.ingredient
        if (-not (Test-ParsecCoreIngredientOperationSupported -Definition $definition -Operation 'reset')) {
            continue
        }

        $rollbackCandidates += [ordered]@{
            step = $step
            step_result = $stepResult
        }
    }

    foreach ($candidate in @($rollbackCandidates)) {
        $resetResult = Invoke-ParsecCoreIngredientOperation -Name $candidate.step.ingredient -Operation 'reset' -Arguments $candidate.step.arguments -Prior $candidate.step_result.operation_result -StateRoot $StateRoot -RunState $RunState
        $rollbackEntry = [ordered]@{
            step_id = $candidate.step.id
            ingredient = $candidate.step.ingredient
            operation = 'reset'
            status = if ($null -ne $resetResult) { [string] $resetResult.Status } else { 'Failed' }
            result = $resetResult
            message = if ($null -ne $resetResult) { $resetResult.Message } else { 'Rollback reset returned no result.' }
        }
        $RunState.compensation_logs += $resetResult
        $rollbackResults += , $rollbackEntry
    }

    return , @($rollbackResults)
}

function Invoke-ParsecRunRecordRollback {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $RunRecord,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $FailedStepResult,

        [Parameter(Mandatory)]
        [object[]] $ExecutedSteps,

        [Parameter(Mandatory)]
        [string] $StateRoot
    )

    $rollbackResults = @()
    foreach ($step in @($ExecutedSteps | Sort-Object sequence -Descending)) {
        $stepResult = Get-ParsecStepResultById -RunState $RunRecord -StepId $step.id
        if ($null -eq $stepResult) {
            continue
        }

        if ($stepResult.step_id -eq $FailedStepResult.step_id) {
            continue
        }

        if (-not (Test-ParsecStepResultRollbackEligible -StepResult $stepResult)) {
            continue
        }

        if ($step.compensation_policy -ne 'explicit' -or [string]::IsNullOrWhiteSpace([string] $stepResult.token_id)) {
            continue
        }

        $definition = Get-ParsecCoreIngredientDefinition -Name $step.ingredient
        if (-not (Test-ParsecCoreIngredientOperationSupported -Definition $definition -Operation 'reset')) {
            continue
        }

        $invocation = Invoke-ParsecIngredientCommandInternal -Name $step.ingredient -Operation 'reset' -TokenId $stepResult.token_id -StateRoot $StateRoot
        $rollbackEntry = [ordered]@{
            step_id = $step.id
            ingredient = $step.ingredient
            operation = 'reset'
            status = [string] $invocation.status
            result = $invocation.reset_result
            message = $invocation.message
            invocation_id = $invocation.invocation_id
            token_id = $stepResult.token_id
        }
        $RunRecord.compensation_logs += $invocation
        $rollbackResults += , $rollbackEntry
    }

    return , @($rollbackResults)
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

    if ($RunState.Contains('rollback_status')) {
        switch ([string] $RunState.rollback_status) {
            'Succeeded' { return 'RolledBack' }
            'Partial' { return 'RollbackDrift' }
            'Failed' { return 'RollbackDrift' }
        }
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
                step_id = $Step.id
                ingredient = $Step.ingredient
                operation = $Step.operation
                status = 'Blocked'
                operation_result = $null
                execution_result = $null
                readiness_result = $null
                verification_result = $null
                compensation_result = $null
                started_at = [DateTimeOffset]::UtcNow.ToString('o')
                completed_at = [DateTimeOffset]::UtcNow.ToString('o')
                message = "Blocked by dependency '$dependency'."
                requested_arguments = ConvertTo-ParsecPlainObject -InputObject $Step.arguments
            }
        }
    }

    if (-not (Test-ParsecStepCondition -Step $Step -RunState $RunState)) {
        return [ordered]@{
            step_id = $Step.id
            ingredient = $Step.ingredient
            operation = $Step.operation
            status = 'Skipped'
            operation_result = $null
            execution_result = $null
            readiness_result = $null
            verification_result = $null
            compensation_result = $null
            started_at = [DateTimeOffset]::UtcNow.ToString('o')
            completed_at = [DateTimeOffset]::UtcNow.ToString('o')
            message = 'Step condition evaluated to false.'
            requested_arguments = ConvertTo-ParsecPlainObject -InputObject $Step.arguments
        }
    }

    $attempt = 0
    $operationResult = $null
    do {
        $attempt++
        $operationResult = Invoke-ParsecCoreIngredientOperation -Name $Step.ingredient -Operation $Step.operation -Arguments $Step.arguments -StateRoot $StateRoot -RunState $RunState
        if ((Test-ParsecSuccessfulStatus -Status $operationResult.Status) -or $attempt -gt $Step.retry_count) {
            break
        }

        if ($Step.retry_delay_ms -gt 0) {
            Start-Sleep -Milliseconds $Step.retry_delay_ms
        }
    }
    while ($true)

    $verificationResult = $null
    $readinessResult = $null
    $finalStatus = $operationResult.Status
    $definition = Get-ParsecCoreIngredientDefinition -Name $Step.ingredient
    $operationOutputs = ConvertTo-ParsecPlainObject -InputObject $operationResult.Outputs
    if ($operationOutputs -is [System.Collections.IDictionary] -and $operationOutputs.Contains('snapshot_name') -and $operationOutputs['snapshot_name']) {
        $RunState.active_snapshot = [string] $operationOutputs['snapshot_name']
    }

    if ($Step.operation -eq 'apply' -and (Test-ParsecSuccessfulStatus -Status $operationResult.Status) -and (Test-ParsecCoreIngredientOperationSupported -Definition $definition -Operation 'wait')) {
        $readinessResult = Wait-ParsecIngredientReadiness -Name $Step.ingredient -Arguments $Step.arguments -ExecutionResult $operationResult -StateRoot $StateRoot -RunState $RunState
        if ($null -ne $readinessResult -and -not (Test-ParsecSuccessfulStatus -Status $readinessResult.Status)) {
            $finalStatus = if ($readinessResult.Status -eq 'Ambiguous') { 'Ambiguous' } else { 'Failed' }
        }
    }

    if ($Step.verify -and (Test-ParsecSuccessfulStatus -Status $finalStatus) -and (Test-ParsecCoreIngredientOperationSupported -Definition $definition -Operation 'verify')) {
        $verificationResult = Invoke-ParsecCoreIngredientOperation -Name $Step.ingredient -Operation 'verify' -Arguments $Step.arguments -Prior $operationResult -StateRoot $StateRoot -RunState $RunState
        if ($null -ne $verificationResult -and -not (Test-ParsecSuccessfulStatus -Status $verificationResult.Status)) {
            $finalStatus = if ($verificationResult.Status -eq 'Ambiguous') { 'Ambiguous' } else { 'SucceededWithDrift' }
        }
    }

    $compensationResult = $null
    if (($finalStatus -eq 'Failed' -or $finalStatus -eq 'Ambiguous') -and $Step.compensation_policy -eq 'explicit' -and (Test-ParsecCoreIngredientOperationSupported -Definition $definition -Operation 'reset')) {
        $compensationResult = Invoke-ParsecCoreIngredientOperation -Name $Step.ingredient -Operation 'reset' -Arguments $Step.arguments -Prior $operationResult -StateRoot $StateRoot -RunState $RunState
        if ($null -ne $compensationResult) {
            $RunState.compensation_logs += $compensationResult
            if (Test-ParsecSuccessfulStatus -Status $compensationResult.Status) {
                $finalStatus = 'Compensated'
            }
        }
    }

    return [ordered]@{
        step_id = $Step.id
        ingredient = $Step.ingredient
        operation = $Step.operation
        status = $finalStatus
        operation_result = $operationResult
        execution_result = $operationResult
        readiness_result = $readinessResult
        verification_result = $verificationResult
        compensation_result = $compensationResult
        started_at = [DateTimeOffset]::UtcNow.ToString('o')
        completed_at = [DateTimeOffset]::UtcNow.ToString('o')
        message = if ($null -ne $verificationResult -and $verificationResult.Message) { $verificationResult.Message } elseif ($null -ne $readinessResult -and $readinessResult.Message) { $readinessResult.Message } else { $operationResult.Message }
        requested_arguments = ConvertTo-ParsecPlainObject -InputObject $Step.arguments
    }
}

function Resolve-ParsecRecipeSequenceTerminalStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $RunRecord
    )

    $statuses = @($RunRecord.step_results | ForEach-Object { $_.status })
    if ($statuses.Count -eq 0) {
        return 'Failed'
    }

    if ($RunRecord.Contains('rollback_status')) {
        switch ([string] $RunRecord.rollback_status) {
            'Succeeded' { return 'RolledBack' }
            'Partial' { return 'RollbackDrift' }
            'Failed' { return 'RollbackDrift' }
        }
    }

    if ($statuses -contains 'Ambiguous') {
        return 'Ambiguous'
    }

    if ($statuses -contains 'Failed' -or $statuses -contains 'Blocked') {
        if ($statuses -contains 'Succeeded' -or $statuses -contains 'Compensated') {
            return 'PartiallyApplied'
        }

        return 'Failed'
    }

    if ($statuses -contains 'Compensated') {
        return 'Compensated'
    }

    if ($statuses -contains 'SucceededWithDrift') {
        return 'SucceededWithDrift'
    }

    return 'Succeeded'
}

function Invoke-ParsecRecipeSequenceStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Step,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $RunRecord,

        [Parameter(Mandatory)]
        [string] $StateRoot
    )

    foreach ($dependency in @($Step.depends_on)) {
        $dependencyResult = Get-ParsecStepResultById -RunState $RunRecord -StepId $dependency
        if ($null -eq $dependencyResult -or -not (Test-ParsecSuccessfulStatus -Status $dependencyResult.status)) {
            return [ordered]@{
                step_id = $Step.id
                ingredient = $Step.ingredient
                operation = $Step.operation
                status = 'Blocked'
                invocation_id = $null
                token_id = $null
                token_path = $null
                capture_result = $null
                operation_result = $null
                execution_result = $null
                readiness_result = $null
                verification_result = $null
                compensation_result = $null
                started_at = [DateTimeOffset]::UtcNow.ToString('o')
                completed_at = [DateTimeOffset]::UtcNow.ToString('o')
                message = "Blocked by dependency '$dependency'."
                requested_arguments = ConvertTo-ParsecPlainObject -InputObject $Step.arguments
            }
        }
    }

    if (-not (Test-ParsecStepCondition -Step $Step -RunState $RunRecord)) {
        return [ordered]@{
            step_id = $Step.id
            ingredient = $Step.ingredient
            operation = $Step.operation
            status = 'Skipped'
            invocation_id = $null
            token_id = $null
            token_path = $null
            capture_result = $null
            operation_result = $null
            execution_result = $null
            readiness_result = $null
            verification_result = $null
            compensation_result = $null
            started_at = [DateTimeOffset]::UtcNow.ToString('o')
            completed_at = [DateTimeOffset]::UtcNow.ToString('o')
            message = 'Step condition evaluated to false.'
            requested_arguments = ConvertTo-ParsecPlainObject -InputObject $Step.arguments
        }
    }

    if ($Step.operation -eq 'apply') {
        $definition = Get-ParsecCoreIngredientDefinition -Name $Step.ingredient
        $attempt = 0
        $invocation = $null
        do {
            $attempt++
            $invocation = Invoke-ParsecIngredientCommandInternal -Name $Step.ingredient -Operation 'apply' -Arguments $Step.arguments -Verify $Step.verify -StateRoot $StateRoot
            if ((Test-ParsecSuccessfulStatus -Status $invocation.status) -or $attempt -gt $Step.retry_count) {
                break
            }

            if ($Step.retry_delay_ms -gt 0) {
                Start-Sleep -Milliseconds $Step.retry_delay_ms
            }
        }
        while ($true)

        $finalStatus = [string] $invocation.status
        $compensationInvocation = $null
        if (($finalStatus -eq 'Failed' -or $finalStatus -eq 'Ambiguous') -and $Step.compensation_policy -eq 'explicit' -and -not [string]::IsNullOrWhiteSpace([string] $invocation.token_id) -and (Test-ParsecCoreIngredientOperationSupported -Definition $definition -Operation 'reset')) {
            $compensationInvocation = Invoke-ParsecIngredientCommandInternal -Name $Step.ingredient -Operation 'reset' -TokenId $invocation.token_id -StateRoot $StateRoot
            if (Test-ParsecSuccessfulStatus -Status $compensationInvocation.status) {
                $finalStatus = 'Compensated'
                $RunRecord.compensation_logs += $compensationInvocation
            }
        }

        return [ordered]@{
            step_id = $Step.id
            ingredient = $invocation.ingredient_name
            operation = $Step.operation
            status = $finalStatus
            invocation_id = $invocation.invocation_id
            token_id = $invocation.token_id
            token_path = $invocation.token_path
            capture_result = $invocation.capture_result
            operation_result = $invocation.operation_result
            execution_result = $invocation.operation_result
            readiness_result = $invocation.readiness_result
            verification_result = $invocation.verify_result
            compensation_result = if ($null -ne $compensationInvocation) { $compensationInvocation.reset_result } else { $null }
            started_at = $invocation.started_at
            completed_at = $invocation.completed_at
            message = if ($null -ne $compensationInvocation) { $compensationInvocation.message } else { $invocation.message }
            requested_arguments = ConvertTo-ParsecPlainObject -InputObject $Step.arguments
        }
    }

    $definition = Get-ParsecCoreIngredientDefinition -Name $Step.ingredient
    $attempt = 0
    $operationResult = $null
    do {
        $attempt++
        $operationResult = Invoke-ParsecCoreIngredientOperation -Name $definition.Name -Operation $Step.operation -Arguments $Step.arguments -StateRoot $StateRoot -RunState $RunRecord
        if ((Test-ParsecSuccessfulStatus -Status $operationResult.Status) -or $attempt -gt $Step.retry_count) {
            break
        }

        if ($Step.retry_delay_ms -gt 0) {
            Start-Sleep -Milliseconds $Step.retry_delay_ms
        }
    }
    while ($true)

    $verificationResult = $null
    $finalStatus = [string] $operationResult.Status
    if ($Step.verify -and $Step.operation -ne 'verify' -and (Test-ParsecSuccessfulStatus -Status $operationResult.Status) -and (Test-ParsecCoreIngredientOperationSupported -Definition $definition -Operation 'verify')) {
        $verificationResult = Invoke-ParsecCoreIngredientOperation -Name $definition.Name -Operation 'verify' -Arguments $Step.arguments -Prior $operationResult -StateRoot $StateRoot -RunState $RunRecord
        if ($null -ne $verificationResult -and -not (Test-ParsecSuccessfulStatus -Status $verificationResult.Status)) {
            $finalStatus = if ($verificationResult.Status -eq 'Ambiguous') { 'Ambiguous' } else { 'Failed' }
        }
    }

    return [ordered]@{
        step_id = $Step.id
        ingredient = $definition.Name
        operation = $Step.operation
        status = $finalStatus
        invocation_id = $null
        token_id = $null
        token_path = $null
        capture_result = $null
        operation_result = $operationResult
        execution_result = $operationResult
        readiness_result = $null
        verification_result = $verificationResult
        compensation_result = $null
        started_at = [DateTimeOffset]::UtcNow.ToString('o')
        completed_at = [DateTimeOffset]::UtcNow.ToString('o')
        message = if ($null -ne $verificationResult -and $verificationResult.Message) { $verificationResult.Message } else { $operationResult.Message }
        requested_arguments = ConvertTo-ParsecPlainObject -InputObject $Step.arguments
    }
}

function Invoke-ParsecRecipeSequence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Recipe,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $stateRoot = Initialize-ParsecStateRoot -StateRoot $StateRoot
    $executorState = Get-ParsecExecutorStateDocument -StateRoot $stateRoot
    $runRecord = @{
        run_id = New-ParsecRunIdentifier
        recipe_name = $Recipe.name
        recipe_file = $Recipe.path
        desired_state = $Recipe.target_mode
        actual_state = $executorState.actual_mode
        active_snapshot = $executorState.active_snapshot
        terminal_status = 'Running'
        started_at = [DateTimeOffset]::UtcNow.ToString('o')
        completed_at = $null
        step_results = @()
        compensation_logs = @()
        rollback_results = @()
        rollback_status = 'NotNeeded'
        validation_errors = @()
    }

    $executionPlan = Resolve-ParsecRecipeExecutionPlan -Recipe $Recipe
    if (-not $executionPlan.valid) {
        $runRecord.validation_errors = @($executionPlan.errors)
        $runRecord.terminal_status = 'Failed'
        $runRecord.completed_at = [DateTimeOffset]::UtcNow.ToString('o')
        return $runRecord
    }

    $orderedSteps = @($executionPlan.ordered_steps)
    $executedSteps = @()
    $stopExecution = $false
    foreach ($step in $orderedSteps) {
        if ($stopExecution) {
            $runRecord.step_results += (New-ParsecBlockedSequenceStepResult -Step $step -Message 'Not executed because a previous step failed and rollback was started.')
            continue
        }

        $stepResult = Invoke-ParsecRecipeSequenceStep -Step $step -RunRecord $runRecord -StateRoot $stateRoot
        $runRecord.step_results += $stepResult
        $executedSteps += , $step

        if ($stepResult.status -eq 'Failed' -or $stepResult.status -eq 'Ambiguous') {
            $runRecord.rollback_results = Invoke-ParsecRunRecordRollback -RunRecord $runRecord -FailedStepResult $stepResult -ExecutedSteps $executedSteps -StateRoot $stateRoot
            $runRecord.rollback_status = Resolve-ParsecRollbackStatus -RollbackResults $runRecord.rollback_results
            $stopExecution = $true
        }
    }

    $runRecord.terminal_status = Resolve-ParsecRecipeSequenceTerminalStatus -RunRecord $runRecord
    $runRecord.completed_at = [DateTimeOffset]::UtcNow.ToString('o')
    return $runRecord
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
        run_id = $runState.run_id
        transition_id = $runState.transition_id
        recipe_name = $Recipe.name
        desired_state = $Recipe.target_mode
        active_snapshot = $runState.active_snapshot
    } -StateRoot $stateRoot | Out-Null

    $executionPlan = Resolve-ParsecRecipeExecutionPlan -Recipe $Recipe
    if (-not $executionPlan.valid) {
        $runState.validation_errors = @($executionPlan.errors)
        $runState.errors += @($executionPlan.errors)
        $runState.terminal_status = 'Failed'
        $runState.transition_phase = 'Completed'
        $runState.actual_state = $executorState.actual_mode
        $runState.last_good_state = $executorState.last_good_mode
        $runState.completed_at = [DateTimeOffset]::UtcNow.ToString('o')
        Save-ParsecRunState -RunState $runState | Out-Null
        $executorState.transition_phase = 'Idle'
        $executorState.last_error = $executionPlan.errors[0]
        Save-ParsecExecutorStateDocument -StateDocument $executorState -StateRoot $stateRoot | Out-Null
        return $runState
    }

    $orderedSteps = @($executionPlan.ordered_steps)
    $executedSteps = @()
    $stopExecution = $false
    foreach ($step in $orderedSteps) {
        if ($stopExecution) {
            $runState.step_results += (New-ParsecBlockedStepResult -Step $step -Message 'Not executed because a previous step failed and rollback was started.')
            continue
        }

        $runState.transition_phase = "Executing:$($step.id)"
        $stepResult = Invoke-ParsecStep -Step $step -RunState $runState -StateRoot $stateRoot
        $runState.step_results += $stepResult
        $executedSteps += , $step
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
            run_id = $runState.run_id
            transition_id = $runState.transition_id
            step_id = $step.id
            ingredient = $step.ingredient
            operation = $step.operation
            status = $stepResult.status
            active_snapshot = $runState.active_snapshot
        } -StateRoot $stateRoot | Out-Null

        if ($stepResult.status -eq 'Failed' -or $stepResult.status -eq 'Ambiguous') {
            $runState.errors += $stepResult.message
        }

        if ($stepResult.status -eq 'SucceededWithDrift') {
            $runState.warnings += $stepResult.message
        }

        if ($stepResult.status -eq 'Failed' -or $stepResult.status -eq 'Ambiguous') {
            $runState.rollback_results = Invoke-ParsecRunStateRollback -RunState $runState -FailedStepResult $stepResult -ExecutedSteps $executedSteps -StateRoot $stateRoot
            $runState.rollback_status = Resolve-ParsecRollbackStatus -RollbackResults $runState.rollback_results
            $stopExecution = $true
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
        run_id = $runState.run_id
        transition_id = $runState.transition_id
        recipe_name = $Recipe.name
        terminal_status = $runState.terminal_status
        actual_state = $runState.actual_state
        last_good_state = $runState.last_good_state
        active_snapshot = $runState.active_snapshot
        transition_phase = $runState.transition_phase
        error_count = @($runState.errors).Count
        warning_count = @($runState.warnings).Count
    } -StateRoot $stateRoot | Out-Null

    return $runState
}
