function Find-ParsecMatchingRecipe {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string] $Username,

        [Parameter(Mandatory)]
        [ValidateSet('connect', 'disconnect')]
        [string] $EventType,

        [Parameter(Mandatory)]
        [array] $Recipes
    )

    $candidates = @()
    foreach ($recipe in $Recipes) {
        if (-not (Test-ParsecRecipeMatchesEvent -Recipe $recipe -Username $Username -EventType $EventType)) {
            continue
        }

        $candidates += $recipe
    }

    if ($candidates.Count -eq 0) {
        return $null
    }

    if ($candidates.Count -gt 1) {
        $usernameMatch = $candidates | Where-Object {
            $_.Contains('username') -and $_.username -eq $Username
        }

        if ($usernameMatch) {
            return @($usernameMatch)[0]
        }
    }

    return $candidates[0]
}

function Test-ParsecRecipeMatchesEvent {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Recipe,

        [Parameter(Mandatory)]
        [string] $Username,

        [Parameter(Mandatory)]
        [ValidateSet('connect', 'disconnect')]
        [string] $EventType
    )

    # Username filter: if recipe specifies a username, it must match
    if ($Recipe.Contains('username') -and $Recipe.username) {
        if ($Recipe.username -ne $Username) {
            return $false
        }
    }

    # Event type matching: recipe must declare event_type and it must match
    if (-not $Recipe.Contains('event_type') -or [string]::IsNullOrEmpty($Recipe.event_type)) {
        return $false
    }

    if ($Recipe.event_type -ne $EventType) {
        return $false
    }

    return $true
}

function Get-ParsecRecipeGracePeriod {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Recipe,

        [Parameter()]
        [int] $DefaultGracePeriodMs = 10000
    )

    if ($Recipe.Contains('grace_period_ms') -and $null -ne $Recipe.grace_period_ms) {
        return [int] $Recipe.grace_period_ms
    }

    return $DefaultGracePeriodMs
}
