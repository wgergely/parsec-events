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
    Write-ParsecJsonFile -Path $path -InputObject $RunState | Out-Null
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
    $document = Read-ParsecJsonFile -Path $path
    if ($null -eq $document) {
        return [ordered]@{
            desired_mode     = $null
            actual_mode      = $null
            last_good_mode   = $null
            transition_id    = $null
            transition_phase = 'Idle'
            last_run_id      = $null
            last_error       = $null
            updated_at       = [DateTimeOffset]::UtcNow.ToString('o')
        }
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
    Write-ParsecJsonFile -Path $path -InputObject $StateDocument | Out-Null
    return $path
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

    $path = Get-ParsecProfileDocumentPath -Name $Name -StateRoot $StateRoot
    Write-ParsecJsonFile -Path $path -InputObject $ProfileDocument | Out-Null
    return $path
}

function Read-ParsecProfileDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $path = Resolve-ParsecProfilePath -Name $Name -StateRoot $StateRoot
    $document = Read-ParsecJsonFile -Path $path
    if ($null -eq $document) {
        throw "Profile '$Name' exists but could not be read."
    }

    return ConvertTo-ParsecPlainObject -InputObject $document
}
