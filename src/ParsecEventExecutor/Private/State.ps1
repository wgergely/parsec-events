function New-ParsecRunState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Recipe,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $runId = New-ParsecRunIdentifier
    return [ordered]@{
        run_id            = $runId
        recipe_name       = $Recipe.name
        recipe_file       = $Recipe.path
        desired_state     = $Recipe.target_mode
        actual_state      = $null
        last_good_state   = $null
        active_snapshot   = $null
        terminal_status   = 'Running'
        transition_id     = $runId
        transition_phase  = 'Starting'
        started_at        = [DateTimeOffset]::UtcNow.ToString('o')
        completed_at      = $null
        step_results      = @()
        compensation_logs = @()
        errors            = @()
        warnings          = @()
        state_root        = (Initialize-ParsecStateRoot -StateRoot $StateRoot)
    }
}

function Save-ParsecRunState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $RunState
    )

    $path = Join-Path -Path $RunState.state_root -ChildPath ("runs/{0}.json" -f $RunState.run_id)
    Write-ParsecStateDocument -Path $path -DocumentType 'run-state' -Payload $RunState | Out-Null
    return $path
}

function Get-ParsecExecutorStateDocument {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $stateRoot = Initialize-ParsecStateRoot -StateRoot $StateRoot
    $path = Join-Path -Path $stateRoot -ChildPath 'executor-state.json'
    $document = Read-ParsecStateDocument -Path $path -ExpectedDocumentType 'executor-state'
    if ($null -eq $document) {
        return [ordered]@{
            desired_mode        = $null
            actual_mode         = $null
            last_good_mode      = $null
            active_snapshot     = $null
            transition_id       = $null
            transition_phase    = 'Idle'
            last_run_id         = $null
            last_error          = $null
            updated_at          = [DateTimeOffset]::UtcNow.ToString('o')
        }
    }

    if ($document -is [System.Collections.IDictionary] -and $document.Contains('payload')) {
        return ConvertTo-ParsecPlainObject -InputObject $document.payload
    }

    return ConvertTo-ParsecPlainObject -InputObject $document
}

function Save-ParsecExecutorStateDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $StateDocument,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $stateRoot = Initialize-ParsecStateRoot -StateRoot $StateRoot
    $path = Join-Path -Path $stateRoot -ChildPath 'executor-state.json'
    $StateDocument.updated_at = [DateTimeOffset]::UtcNow.ToString('o')
    Write-ParsecStateDocument -Path $path -DocumentType 'executor-state' -Payload $StateDocument | Out-Null
    return $path
}

function Save-ParsecSnapshotDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [hashtable] $SnapshotDocument,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $path = Get-ParsecSnapshotDocumentPath -Name $Name -StateRoot $StateRoot
    Write-ParsecStateDocument -Path $path -DocumentType 'snapshot-state' -Payload $SnapshotDocument | Out-Null
    return $path
}

function Read-ParsecSnapshotDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $path = Resolve-ParsecSnapshotPath -Name $Name -StateRoot $StateRoot
    $document = Read-ParsecStateDocument -Path $path -ExpectedDocumentType 'snapshot-state'
    if ($null -eq $document) {
        throw "Snapshot '$Name' exists but could not be read."
    }

    if ($document -is [System.Collections.IDictionary] -and $document.Contains('payload')) {
        return ConvertTo-ParsecPlainObject -InputObject $document.payload
    }

    return ConvertTo-ParsecPlainObject -InputObject $document
}

function Get-ParsecRunStateDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $RunId,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $stateRoot = Initialize-ParsecStateRoot -StateRoot $StateRoot
    $path = Join-Path -Path $stateRoot -ChildPath ("runs/{0}.json" -f $RunId)
    $document = Read-ParsecStateDocument -Path $path -ExpectedDocumentType 'run-state'
    if ($null -eq $document) {
        return $null
    }

    if ($document -is [System.Collections.IDictionary] -and $document.Contains('payload')) {
        return ConvertTo-ParsecPlainObject -InputObject $document.payload
    }

    return ConvertTo-ParsecPlainObject -InputObject $document
}

function Get-ParsecRecoveryStatus {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $state = Get-ParsecExecutorStateDocument -StateRoot $StateRoot
    $issues = New-Object System.Collections.Generic.List[string]
    $lastRun = $null

    if ($state.last_run_id) {
        $lastRun = Get-ParsecRunStateDocument -RunId $state.last_run_id -StateRoot $StateRoot
        if ($null -eq $lastRun) {
            $issues.Add("Last run '$($state.last_run_id)' is missing.")
        }
    }

    if ($state.active_snapshot) {
        $snapshotPath = Get-ParsecSnapshotDocumentPath -Name $state.active_snapshot -StateRoot $StateRoot
        if (-not (Test-Path -LiteralPath $snapshotPath)) {
            $issues.Add("Active snapshot '$($state.active_snapshot)' is missing.")
        }
    }

    if ($state.transition_phase -and $state.transition_phase -ne 'Idle') {
        $issues.Add("Executor transition phase is '$($state.transition_phase)'.")
    }

    if ($null -ne $lastRun -and $lastRun.transition_phase -and $lastRun.transition_phase -ne 'Completed') {
        $issues.Add("Last run '$($lastRun.run_id)' did not complete cleanly.")
    }

    if ($null -ne $lastRun -and $state.transition_id -and $lastRun.transition_id -ne $state.transition_id) {
        $issues.Add('Executor state and last run transition ids differ.')
    }

    $recoveryCandidate = Get-ParsecRecoveryCandidateFromEvents -StateRoot $StateRoot
    $isRecoverable = $recoveryCandidate.recovered_from_journal -and $issues.Count -gt 0

    return [ordered]@{
        desired_mode      = $state.desired_mode
        actual_mode       = $state.actual_mode
        last_good_mode    = $state.last_good_mode
        active_snapshot   = $state.active_snapshot
        last_run_id       = $state.last_run_id
        issues            = @($issues)
        recovery_candidate = $recoveryCandidate
        recoverable       = $isRecoverable
        status            = if ($issues.Count -eq 0) { 'Converged' } elseif ($isRecoverable) { 'RecoverableDrift' } else { 'NeedsIntervention' }
        checked_at        = [DateTimeOffset]::UtcNow.ToString('o')
    }
}

function Get-ParsecEventDocuments {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $stateRoot = Initialize-ParsecStateRoot -StateRoot $StateRoot
    $eventsPath = Join-Path -Path $stateRoot -ChildPath 'events'
    if (-not (Test-Path -LiteralPath $eventsPath)) {
        return @()
    }

    $documents = foreach ($file in (Get-ChildItem -Path $eventsPath -File | Sort-Object Name)) {
        $document = Read-ParsecStateDocument -Path $file.FullName
        if ($null -eq $document) {
            continue
        }

        if ($document -is [System.Collections.IDictionary] -and $document.Contains('envelope') -and $document.Contains('payload')) {
            [ordered]@{
                file_path = $file.FullName
                envelope  = ConvertTo-ParsecPlainObject -InputObject $document.envelope
                payload   = ConvertTo-ParsecPlainObject -InputObject $document.payload
            }
        }
        else {
            [ordered]@{
                file_path = $file.FullName
                envelope  = $null
                payload   = ConvertTo-ParsecPlainObject -InputObject $document
            }
        }
    }

    return @($documents)
}

function Get-ParsecRecoveryCandidateFromEvents {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $candidate = [ordered]@{
        desired_mode        = $null
        actual_mode         = $null
        last_good_mode      = $null
        active_snapshot     = $null
        transition_id       = $null
        transition_phase    = 'Idle'
        last_run_id         = $null
        last_error          = $null
        recovered_from_journal = $false
        recovered_at        = [DateTimeOffset]::UtcNow.ToString('o')
    }

    foreach ($eventRecord in @(Get-ParsecEventDocuments -StateRoot $StateRoot)) {
        $eventType = if ($eventRecord.envelope) { $eventRecord.envelope.document_type } else { $null }
        $payload = $eventRecord.payload
        switch ($eventType) {
            'executor-run-started' {
                $candidate.desired_mode = $payload.desired_state
                $candidate.transition_id = $payload.transition_id
                $candidate.transition_phase = 'Running'
                $candidate.last_run_id = $payload.run_id
                if ($payload.active_snapshot) {
                    $candidate.active_snapshot = $payload.active_snapshot
                }
                $candidate.recovered_from_journal = $true
            }
            'executor-step-completed' {
                $candidate.transition_id = $payload.transition_id
                $candidate.transition_phase = 'Running'
                $candidate.last_run_id = $payload.run_id
                if ($payload.active_snapshot) {
                    $candidate.active_snapshot = $payload.active_snapshot
                }
                if ($payload.status -eq 'Failed' -or $payload.status -eq 'Ambiguous') {
                    $candidate.last_error = "Step '$($payload.step_id)' completed with status '$($payload.status)'."
                }
                $candidate.recovered_from_journal = $true
            }
            'executor-run-completed' {
                $candidate.transition_id = $payload.transition_id
                $candidate.transition_phase = 'Idle'
                $candidate.last_run_id = $payload.run_id
                $candidate.actual_mode = $payload.actual_state
                $candidate.last_good_mode = $payload.last_good_state
                if ($payload.active_snapshot) {
                    $candidate.active_snapshot = $payload.active_snapshot
                }
                if ($payload.terminal_status -eq 'Failed' -or $payload.terminal_status -eq 'Ambiguous') {
                    $candidate.last_error = "Run '$($payload.run_id)' completed with status '$($payload.terminal_status)'."
                }
                $candidate.recovered_from_journal = $true
            }
        }
    }

    return $candidate
}

function Repair-ParsecExecutorStateDocumentInternal {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $candidate = Get-ParsecRecoveryCandidateFromEvents -StateRoot $StateRoot
    if (-not $candidate.recovered_from_journal) {
        return [ordered]@{
            status     = 'NoRecoveryData'
            state_root = $StateRoot
            repaired   = $false
            candidate  = $candidate
        }
    }

    Save-ParsecExecutorStateDocument -StateDocument $candidate -StateRoot $StateRoot | Out-Null
    return [ordered]@{
        status      = 'Recovered'
        state_root  = $StateRoot
        repaired    = $true
        candidate   = $candidate
        repaired_at = [DateTimeOffset]::UtcNow.ToString('o')
    }
}

function Save-ParsecProfileDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [hashtable] $ProfileDocument,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    return Save-ParsecSnapshotDocument -Name $Name -SnapshotDocument $ProfileDocument -StateRoot $StateRoot
}

function Read-ParsecProfileDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    return Read-ParsecSnapshotDocument -Name $Name -StateRoot $StateRoot
}
