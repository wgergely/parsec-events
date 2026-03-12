function Get-ParsecIngredientInvocationDocumentPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $InvocationId,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $stateRoot = Initialize-ParsecStateRoot -StateRoot $StateRoot
    return Join-Path -Path $stateRoot -ChildPath ("ingredient-invocations/{0}.json" -f $InvocationId)
}

function Save-ParsecIngredientInvocationDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $InvocationDocument,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $path = Get-ParsecIngredientInvocationDocumentPath -InvocationId $InvocationDocument.invocation_id -StateRoot $StateRoot
    Write-ParsecStateDocument -Path $path -DocumentType 'ingredient-invocation' -Payload $InvocationDocument | Out-Null
    return $path
}

function Get-ParsecIngredientTokenDocumentPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $TokenId,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $stateRoot = Initialize-ParsecStateRoot -StateRoot $StateRoot
    return Join-Path -Path $stateRoot -ChildPath ("ingredient-tokens/{0}.json" -f $TokenId)
}

function Save-ParsecIngredientTokenDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $TokenDocument,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $TokenDocument.updated_at = [DateTimeOffset]::UtcNow.ToString('o')
    $path = Get-ParsecIngredientTokenDocumentPath -TokenId $TokenDocument.token_id -StateRoot $StateRoot
    Write-ParsecStateDocument -Path $path -DocumentType 'ingredient-token' -Payload $TokenDocument | Out-Null
    return $path
}

function Read-ParsecIngredientTokenDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $TokenId,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $path = Get-ParsecIngredientTokenDocumentPath -TokenId $TokenId -StateRoot $StateRoot
    $document = Read-ParsecStateDocument -Path $path -ExpectedDocumentType 'ingredient-token'
    if ($null -eq $document) {
        throw "Ingredient token '$TokenId' could not be found."
    }

    if ($document -is [System.Collections.IDictionary] -and $document.Contains('payload')) {
        return ConvertTo-ParsecPlainObject -InputObject $document.payload
    }

    return ConvertTo-ParsecPlainObject -InputObject $document
}

function Get-ParsecDisplayCatalogDocumentPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $stateRoot = Initialize-ParsecStateRoot -StateRoot $StateRoot
    return Join-Path -Path $stateRoot -ChildPath 'display-catalog.json'
}

function Get-ParsecDisplayCatalogDocument {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $path = Get-ParsecDisplayCatalogDocumentPath -StateRoot $StateRoot
    $document = Read-ParsecStateDocument -Path $path -ExpectedDocumentType 'display-catalog'
    if ($null -eq $document) {
        return [ordered]@{
            entries = @()
            updated_at = [DateTimeOffset]::UtcNow.ToString('o')
        }
    }

    if ($document -is [System.Collections.IDictionary] -and $document.Contains('payload')) {
        return ConvertTo-ParsecPlainObject -InputObject $document.payload
    }

    return ConvertTo-ParsecPlainObject -InputObject $document
}

function Save-ParsecDisplayCatalogDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $CatalogDocument,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $CatalogDocument.updated_at = [DateTimeOffset]::UtcNow.ToString('o')
    $path = Get-ParsecDisplayCatalogDocumentPath -StateRoot $StateRoot
    Write-ParsecStateDocument -Path $path -DocumentType 'display-catalog' -Payload $CatalogDocument | Out-Null
    return $path
}

function Get-ParsecDisplayMonitorIdentityRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Monitor
    )

    if ($Monitor.Contains('identity') -and $Monitor.identity -is [System.Collections.IDictionary]) {
        return ConvertTo-ParsecPlainObject -InputObject $Monitor.identity
    }

    if ($Monitor.Contains('monitor_device_path') -and -not [string]::IsNullOrWhiteSpace([string] $Monitor.monitor_device_path)) {
        return [ordered]@{
            scheme = 'monitor_device_path'
            monitor_device_path = [string] $Monitor.monitor_device_path
            source_name = if ($Monitor.Contains('source_name')) { [string] $Monitor.source_name } else { $null }
        }
    }

    return [ordered]@{
        scheme = 'device_name'
        device_name = if ($Monitor.Contains('device_name')) { [string] $Monitor.device_name } else { $null }
    }
}

function Get-ParsecDisplayMonitorIdentityKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Monitor
    )

    $identity = Get-ParsecDisplayMonitorIdentityRecord -Monitor $Monitor
    switch ([string] $identity.scheme) {
        'adapter_id+target_id' {
            return "adapter_id+target_id:{0}:{1}" -f [string] $identity.adapter_id, [string] $identity.target_id
        }
        'monitor_device_path' {
            return "monitor_device_path:{0}" -f [string] $identity.monitor_device_path
        }
        default {
            return "device_name:{0}" -f [string] $identity.device_name
        }
    }
}

function Test-ParsecDisplayCatalogValueEqual {
    [CmdletBinding()]
    param(
        [Parameter()]
        $Left,

        [Parameter()]
        $Right
    )

    if ($null -eq $Left -and $null -eq $Right) {
        return $true
    }

    if ($null -eq $Left -or $null -eq $Right) {
        return $false
    }

    $leftJson = ConvertTo-ParsecPlainObject -InputObject $Left | ConvertTo-Json -Depth 100 -Compress
    $rightJson = ConvertTo-ParsecPlainObject -InputObject $Right | ConvertTo-Json -Depth 100 -Compress
    return $leftJson -ceq $rightJson
}

function Find-ParsecDisplayCatalogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable] $Entries,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Monitor
    )

    $identity = Get-ParsecDisplayMonitorIdentityRecord -Monitor $Monitor
    $identityKey = Get-ParsecDisplayMonitorIdentityKey -Monitor $Monitor
    $monitorDeviceName = if ($Monitor.Contains('device_name')) { [string] $Monitor.device_name } else { $null }
    $monitorDevicePath = if ($identity.Contains('monitor_device_path')) { [string] $identity.monitor_device_path } else { $null }
    $monitorAdapterId = if ($identity.Contains('adapter_id')) { [string] $identity.adapter_id } else { $null }
    $monitorTargetId = if ($identity.Contains('target_id')) { [string] $identity.target_id } else { $null }

    $exactMatch = $Entries | Where-Object { $_.identity_key -eq $identityKey } | Select-Object -First 1
    if ($null -ne $exactMatch) {
        return $exactMatch
    }

    foreach ($entry in @($Entries)) {
        $entryIdentity = if ($entry.Contains('identity') -and $entry.identity -is [System.Collections.IDictionary]) {
            ConvertTo-ParsecPlainObject -InputObject $entry.identity
        }
        else {
            @{}
        }

        if (
            -not [string]::IsNullOrWhiteSpace($monitorDevicePath) -and
            $entryIdentity.Contains('monitor_device_path') -and
            [string] $entryIdentity.monitor_device_path -eq $monitorDevicePath
        ) {
            return $entry
        }

        if (
            -not [string]::IsNullOrWhiteSpace($monitorAdapterId) -and
            -not [string]::IsNullOrWhiteSpace($monitorTargetId) -and
            $entryIdentity.Contains('adapter_id') -and
            $entryIdentity.Contains('target_id') -and
            [string] $entryIdentity.adapter_id -eq $monitorAdapterId -and
            [string] $entryIdentity.target_id -eq $monitorTargetId
        ) {
            return $entry
        }

        if (
            -not [string]::IsNullOrWhiteSpace($monitorDeviceName) -and (
                ($entryIdentity.Contains('device_name') -and [string] $entryIdentity.device_name -eq $monitorDeviceName) -or
                ($entry.Contains('device_name') -and [string] $entry.device_name -eq $monitorDeviceName)
            )
        ) {
            return $entry
        }
    }

    return $null
}

function Sync-ParsecDisplayCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ObservedState,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $catalog = Get-ParsecDisplayCatalogDocument -StateRoot $StateRoot
    $entries = @()
    foreach ($entry in @($catalog.entries)) {
        $entries += , (ConvertTo-ParsecPlainObject -InputObject $entry)
    }

    $changed = $false
    $highestScreenId = 0
    $timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    foreach ($entry in @($entries)) {
        if ($entry.screen_id -gt $highestScreenId) {
            $highestScreenId = [int] $entry.screen_id
        }
    }

    foreach ($monitor in @($ObservedState.monitors)) {
        $identity = Get-ParsecDisplayMonitorIdentityRecord -Monitor $monitor
        $identityKey = Get-ParsecDisplayMonitorIdentityKey -Monitor $monitor
        $entry = Find-ParsecDisplayCatalogEntry -Entries $entries -Monitor $monitor
        if ($null -eq $entry) {
            $highestScreenId++
            $entry = [ordered]@{
                screen_id = [int] $highestScreenId
                identity_key = $identityKey
                identity = $identity
                first_seen_at = $timestamp
                last_seen_at = $timestamp
                device_name = if ($monitor.Contains('device_name')) { [string] $monitor.device_name } else { $null }
                friendly_name = if ($monitor.Contains('friendly_name')) { [string] $monitor.friendly_name } else { $null }
                is_primary = if ($monitor.Contains('is_primary')) { [bool] $monitor.is_primary } else { $false }
                enabled = if ($monitor.Contains('enabled')) { [bool] $monitor.enabled } else { $false }
            }
            $entries += , $entry
            $changed = $true
        }
        else {
            $candidateValues = [ordered]@{
                identity_key = $identityKey
                identity = $identity
                device_name = if ($monitor.Contains('device_name')) { [string] $monitor.device_name } else { $null }
                friendly_name = if ($monitor.Contains('friendly_name')) { [string] $monitor.friendly_name } else { $null }
                is_primary = if ($monitor.Contains('is_primary')) { [bool] $monitor.is_primary } else { $false }
                enabled = if ($monitor.Contains('enabled')) { [bool] $monitor.enabled } else { $false }
            }

            $entryChanged = $false
            foreach ($key in @($candidateValues.Keys)) {
                $currentValue = if ($entry.Contains($key)) { $entry[$key] } else { $null }
                if (-not (Test-ParsecDisplayCatalogValueEqual -Left $currentValue -Right $candidateValues[$key])) {
                    $entry[$key] = $candidateValues[$key]
                    $entryChanged = $true
                }
            }

            if ($entryChanged) {
                $entry.last_seen_at = $timestamp
                $changed = $true
            }
        }
    }

    $result = [ordered]@{
        entries = @($entries)
        updated_at = if ($changed) { $timestamp } elseif ($catalog.Contains('updated_at')) { [string] $catalog.updated_at } else { $timestamp }
    }

    if ($changed) {
        Save-ParsecDisplayCatalogDocument -CatalogDocument $result -StateRoot $StateRoot | Out-Null
    }

    return $result
}

function Resolve-ParsecDisplayMonitorByScreenId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ObservedState,

        [Parameter(Mandatory)]
        [int] $ScreenId,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $catalog = Sync-ParsecDisplayCatalog -ObservedState $ObservedState -StateRoot $StateRoot
    $entry = $catalog.entries | Where-Object { [int] $_.screen_id -eq $ScreenId } | Select-Object -First 1
    if ($null -eq $entry) {
        return $null
    }

    foreach ($monitor in @($ObservedState.monitors)) {
        if ((Get-ParsecDisplayMonitorIdentityKey -Monitor $monitor) -eq $entry.identity_key) {
            return $monitor
        }
    }

    return $null
}

function Get-ParsecDisplayInventory {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $observed = Get-ParsecObservedState
    $catalog = Sync-ParsecDisplayCatalog -ObservedState $observed -StateRoot $StateRoot
    return @(
        foreach ($monitor in @($observed.monitors)) {
            $identityKey = Get-ParsecDisplayMonitorIdentityKey -Monitor $monitor
            $catalogEntry = $catalog.entries | Where-Object { $_.identity_key -eq $identityKey } | Select-Object -First 1
            [pscustomobject]@{
                screen_id = if ($null -ne $catalogEntry) { [int] $catalogEntry.screen_id } else { $null }
                device_name = if ($monitor.Contains('device_name')) { [string] $monitor.device_name } else { $null }
                source_name = if ($monitor.Contains('source_name')) { [string] $monitor.source_name } else { $null }
                friendly_name = if ($monitor.Contains('friendly_name')) { [string] $monitor.friendly_name } else { $null }
                is_primary = if ($monitor.Contains('is_primary')) { [bool] $monitor.is_primary } else { $false }
                enabled = if ($monitor.Contains('enabled')) { [bool] $monitor.enabled } else { $false }
                orientation = if ($monitor.Contains('orientation')) { [string] $monitor.orientation } else { $null }
                bounds = if ($monitor.Contains('bounds')) { ConvertTo-ParsecPlainObject -InputObject $monitor.bounds } else { $null }
                working_area = if ($monitor.Contains('working_area')) { ConvertTo-ParsecPlainObject -InputObject $monitor.working_area } else { $null }
                display = if ($monitor.Contains('display')) { ConvertTo-ParsecPlainObject -InputObject $monitor.display } else { $null }
                identity = Get-ParsecDisplayMonitorIdentityRecord -Monitor $monitor
                identity_key = $identityKey
                monitor_backend = if ($observed.Contains('display_backend')) { [string] $observed.display_backend } else { $null }
            }
        }
    )
}

function Get-ParsecInvocationResolvedTargetIdentity {
    [CmdletBinding()]
    param(
        [Parameter()]
        $ExecutionResult
    )

    $capturedState = Get-ParsecCapturedStateFromResult -ExecutionResult $ExecutionResult
    if ($null -eq $capturedState) {
        return $null
    }

    if ($capturedState -is [System.Collections.IDictionary] -and $capturedState.Contains('identity')) {
        return ConvertTo-ParsecPlainObject -InputObject $capturedState.identity
    }

    if ($capturedState -is [System.Collections.IDictionary] -and $capturedState.Contains('device_name')) {
        return [ordered]@{
            scheme = 'device_name'
            device_name = [string] $capturedState.device_name
        }
    }

    return $null
}

function Get-ParsecIngredientInvocationMessage {
    [CmdletBinding()]
    param(
        [Parameter()]
        $OperationResult,

        [Parameter()]
        $ReadinessResult,

        [Parameter()]
        $VerificationResult,

        [Parameter()]
        $ResetResult
    )

    if ($null -ne $ResetResult -and $ResetResult.Message) {
        return [string] $ResetResult.Message
    }

    if ($null -ne $VerificationResult -and $VerificationResult.Message) {
        return [string] $VerificationResult.Message
    }

    if ($null -ne $ReadinessResult -and $ReadinessResult.Message) {
        return [string] $ReadinessResult.Message
    }

    if ($null -ne $OperationResult -and $OperationResult.Message) {
        return [string] $OperationResult.Message
    }

    return $null
}

function Get-ParsecIngredientReadinessConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Definition
    )

    $configured = @{}
    if ($Definition.PSObject.Properties.Name -contains 'Readiness' -and $Definition.Readiness -is [System.Collections.IDictionary]) {
        $configured = ConvertTo-ParsecPlainObject -InputObject $Definition.Readiness
    }

    return [ordered]@{
        timeout_ms = if ($configured.Contains('timeout_ms') -and [int] $configured.timeout_ms -gt 0) { [int] $configured.timeout_ms } else { 4000 }
        poll_interval_ms = if ($configured.Contains('poll_interval_ms') -and [int] $configured.poll_interval_ms -gt 0) { [int] $configured.poll_interval_ms } else { 200 }
        success_count = if ($configured.Contains('success_count') -and [int] $configured.success_count -gt 0) { [int] $configured.success_count } else { 1 }
    }
}

function Wait-ParsecIngredientReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{}
    )

    $definition = Get-ParsecIngredientDefinition -Name $Name
    if (-not (Test-ParsecIngredientOperationSupported -Definition $definition -Operation 'wait')) {
        return $null
    }

    $configuration = Get-ParsecIngredientReadinessConfiguration -Definition $definition
    $deadline = [DateTimeOffset]::UtcNow.AddMilliseconds([double] $configuration.timeout_ms)
    $attempt = 0
    $successStreak = 0
    $maxSuccessStreak = 0
    $lastProbe = $null

    while ($true) {
        $attempt++
        $lastProbe = Invoke-ParsecIngredientOperation -Name $definition.Name -Operation 'wait' -Arguments $Arguments -ExecutionResult $ExecutionResult -StateRoot $StateRoot -RunState $RunState
        if (Test-ParsecSuccessfulStatus -Status $lastProbe.Status) {
            $successStreak++
            if ($successStreak -gt $maxSuccessStreak) {
                $maxSuccessStreak = $successStreak
            }
        }
        else {
            $successStreak = 0
        }

        if ($successStreak -ge $configuration.success_count) {
            return New-ParsecResult -Status 'Succeeded' -Message ("Ingredient '{0}' reached readiness after {1} probe(s)." -f $definition.Name, $attempt) -Requested $Arguments -Observed (ConvertTo-ParsecPlainObject -InputObject $lastProbe.Observed) -Outputs @{
                attempts = $attempt
                timeout_ms = $configuration.timeout_ms
                poll_interval_ms = $configuration.poll_interval_ms
                success_count = $configuration.success_count
                max_success_streak = $maxSuccessStreak
                successful_probes = $successStreak
                last_probe = ConvertTo-ParsecPlainObject -InputObject $lastProbe
            }
        }

        if ([DateTimeOffset]::UtcNow -ge $deadline) {
            break
        }

        Start-Sleep -Milliseconds $configuration.poll_interval_ms
    }

    $lastProbeMessage = if ($null -ne $lastProbe -and $lastProbe.Message) { [string] $lastProbe.Message } else { 'No readiness probe result was recorded.' }
    return New-ParsecResult -Status 'Failed' -Message ("Timed out waiting for ingredient '{0}' readiness after {1} ms. Last probe: {2}" -f $definition.Name, $configuration.timeout_ms, $lastProbeMessage) -Requested $Arguments -Observed $(if ($null -ne $lastProbe) { ConvertTo-ParsecPlainObject -InputObject $lastProbe.Observed } else { @{} }) -Outputs @{
        attempts = $attempt
        timeout_ms = $configuration.timeout_ms
        poll_interval_ms = $configuration.poll_interval_ms
        success_count = $configuration.success_count
        max_success_streak = $maxSuccessStreak
        successful_probes = $successStreak
        last_probe = ConvertTo-ParsecPlainObject -InputObject $lastProbe
    } -Errors @('ReadinessTimeout')
}

function Invoke-ParsecIngredientCommandInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [ValidateSet('apply', 'capture', 'verify', 'reset')]
        [string] $Operation = 'apply',

        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $TokenId,

        [Parameter()]
        [bool] $Verify = $true,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $stateRoot = Initialize-ParsecStateRoot -StateRoot $StateRoot
    $invocationId = New-ParsecRunIdentifier
    $startedAt = [DateTimeOffset]::UtcNow.ToString('o')
    $definition = Get-ParsecIngredientDefinition -Name $Name
    $captureResult = $null
    $operationResult = $null
    $readinessResult = $null
    $verificationResult = $null
    $resetResult = $null
    $resolvedTargetIdentity = $null
    $finalTokenId = $TokenId
    $persistApplyToken = $false
    $tokenPath = $null
    $requestedArguments = ConvertTo-ParsecPlainObject -InputObject $Arguments
    $finalStatus = 'Failed'

    switch ($Operation) {
        'apply' {
            if (Test-ParsecIngredientOperationSupported -Definition $definition -Operation 'capture') {
                $captureResult = Invoke-ParsecIngredientOperation -Name $definition.Name -Operation 'capture' -Arguments $Arguments -StateRoot $stateRoot -RunState @{}
                if (-not (Test-ParsecSuccessfulStatus -Status $captureResult.Status)) {
                    $operationResult = $captureResult
                    $finalStatus = [string] $captureResult.Status
                    break
                }

                $resolvedTargetIdentity = Get-ParsecInvocationResolvedTargetIdentity -ExecutionResult $captureResult
                $finalTokenId = New-ParsecRunIdentifier
                $tokenDocument = [ordered]@{
                    token_id = $finalTokenId
                    ingredient_name = $definition.Name
                    requested_name = $Name
                    requested_arguments = $requestedArguments
                    resolved_target_identity = $resolvedTargetIdentity
                    captured_state = Get-ParsecCapturedStateFromResult -ExecutionResult $captureResult
                    capture_result = ConvertTo-ParsecPlainObject -InputObject $captureResult
                    apply_result = $null
                    readiness_result = $null
                    verify_result = $null
                    reset_result = $null
                    reset_status = 'Available'
                    created_at = [DateTimeOffset]::UtcNow.ToString('o')
                    updated_at = [DateTimeOffset]::UtcNow.ToString('o')
                }
                $tokenPath = Save-ParsecIngredientTokenDocument -TokenDocument $tokenDocument -StateRoot $stateRoot
                $persistApplyToken = $true
            }

            $operationResult = Invoke-ParsecIngredientOperation -Name $definition.Name -Operation 'apply' -Arguments $Arguments -StateRoot $stateRoot -RunState @{}
            $finalStatus = [string] $operationResult.Status

            if ((Test-ParsecSuccessfulStatus -Status $operationResult.Status) -and (Test-ParsecIngredientOperationSupported -Definition $definition -Operation 'wait')) {
                $readinessResult = Wait-ParsecIngredientReadiness -Name $definition.Name -Arguments $Arguments -ExecutionResult $operationResult -StateRoot $stateRoot -RunState @{}
                if (-not (Test-ParsecSuccessfulStatus -Status $readinessResult.Status)) {
                    $finalStatus = if ($readinessResult.Status -eq 'Ambiguous') { 'Ambiguous' } else { 'Failed' }
                }
            }

            if ($Verify -and (Test-ParsecSuccessfulStatus -Status $finalStatus) -and (Test-ParsecIngredientOperationSupported -Definition $definition -Operation 'verify')) {
                $verificationResult = Invoke-ParsecIngredientOperation -Name $definition.Name -Operation 'verify' -Arguments $Arguments -ExecutionResult $operationResult -StateRoot $stateRoot -RunState @{}
                if (-not (Test-ParsecSuccessfulStatus -Status $verificationResult.Status)) {
                    $finalStatus = if ($verificationResult.Status -eq 'Ambiguous') { 'Ambiguous' } else { 'Failed' }
                }
            }

            if ($persistApplyToken -and $finalTokenId) {
                $tokenDocument = Read-ParsecIngredientTokenDocument -TokenId $finalTokenId -StateRoot $stateRoot
                $tokenDocument.apply_result = ConvertTo-ParsecPlainObject -InputObject $operationResult
                $tokenDocument.readiness_result = ConvertTo-ParsecPlainObject -InputObject $readinessResult
                $tokenDocument.verify_result = ConvertTo-ParsecPlainObject -InputObject $verificationResult
                $tokenDocument.apply_status = $finalStatus
                $tokenPath = Save-ParsecIngredientTokenDocument -TokenDocument $tokenDocument -StateRoot $stateRoot
            }
            elseif (-not $persistApplyToken) {
                $finalTokenId = $null
            }
        }
        'capture' {
            $operationResult = Invoke-ParsecIngredientOperation -Name $definition.Name -Operation 'capture' -Arguments $Arguments -StateRoot $stateRoot -RunState @{}
            $resolvedTargetIdentity = Get-ParsecInvocationResolvedTargetIdentity -ExecutionResult $operationResult
            $finalStatus = [string] $operationResult.Status
        }
        'verify' {
            $operationResult = Invoke-ParsecIngredientOperation -Name $definition.Name -Operation 'verify' -Arguments $Arguments -StateRoot $stateRoot -RunState @{}
            $finalStatus = [string] $operationResult.Status
        }
        'reset' {
            if ([string]::IsNullOrWhiteSpace($TokenId)) {
                throw "Ingredient '$($definition.Name)' reset requires -TokenId."
            }

            $tokenDocument = Read-ParsecIngredientTokenDocument -TokenId $TokenId -StateRoot $stateRoot
            if ($tokenDocument.ingredient_name -ne $definition.Name) {
                throw "Ingredient token '$TokenId' belongs to '$($tokenDocument.ingredient_name)', not '$($definition.Name)'."
            }

            $resolvedTargetIdentity = ConvertTo-ParsecPlainObject -InputObject $tokenDocument.resolved_target_identity
            $resetArguments = Merge-ParsecRecipeMap -Base ([ordered]@{ captured_state = $tokenDocument.captured_state }) -Override (Merge-ParsecRecipeMap -Base $tokenDocument.requested_arguments -Override $Arguments)
            $operationResult = Invoke-ParsecIngredientOperation -Name $definition.Name -Operation 'reset' -Arguments $resetArguments -StateRoot $stateRoot -RunState @{}
            $resetResult = $operationResult
            $finalStatus = [string] $operationResult.Status

            $tokenDocument.reset_result = ConvertTo-ParsecPlainObject -InputObject $resetResult
            $tokenDocument.reset_status = if (Test-ParsecSuccessfulStatus -Status $resetResult.Status) { 'ResetSucceeded' } else { 'ResetFailed' }
            $tokenDocument.reset_invocation_id = $invocationId
            $tokenDocument.reset_at = [DateTimeOffset]::UtcNow.ToString('o')
            $tokenPath = Save-ParsecIngredientTokenDocument -TokenDocument $tokenDocument -StateRoot $stateRoot
        }
    }

    $record = [ordered]@{
        invocation_id = $invocationId
        requested_name = $Name
        ingredient_name = $definition.Name
        operation = $Operation
        status = $finalStatus
        token_id = $finalTokenId
        token_path = $tokenPath
        requested_arguments = $requestedArguments
        resolved_target_identity = $resolvedTargetIdentity
        capture_result = ConvertTo-ParsecPlainObject -InputObject $captureResult
        operation_result = ConvertTo-ParsecPlainObject -InputObject $operationResult
        readiness_result = ConvertTo-ParsecPlainObject -InputObject $readinessResult
        verify_result = ConvertTo-ParsecPlainObject -InputObject $verificationResult
        reset_result = ConvertTo-ParsecPlainObject -InputObject $resetResult
        started_at = $startedAt
        completed_at = [DateTimeOffset]::UtcNow.ToString('o')
        message = Get-ParsecIngredientInvocationMessage -OperationResult $operationResult -ReadinessResult $readinessResult -VerificationResult $verificationResult -ResetResult $resetResult
    }

    $path = Save-ParsecIngredientInvocationDocument -InvocationDocument $record -StateRoot $stateRoot
    $record.invocation_path = $path
    return $record
}
