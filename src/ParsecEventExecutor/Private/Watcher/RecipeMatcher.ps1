function Find-ParsecMatchingRecipe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Username,

        [Parameter(Mandatory)]
        [ValidateSet('DESKTOP', 'MOBILE')]
        [string] $CurrentMode,

        [Parameter(Mandatory)]
        [string] $EventType,

        [Parameter(Mandatory)]
        [array] $Recipes
    )

    $candidates = @()
    foreach ($recipe in $Recipes) {
        if (-not (Test-ParsecRecipeMatchesEvent -Recipe $recipe -Username $Username -CurrentMode $CurrentMode -EventType $EventType)) {
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
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Recipe,

        [Parameter(Mandatory)]
        [string] $Username,

        [Parameter(Mandatory)]
        [ValidateSet('DESKTOP', 'MOBILE')]
        [string] $CurrentMode,

        [Parameter(Mandatory)]
        [ValidateSet('connect', 'disconnect')]
        [string] $EventType
    )

    if ($Recipe.Contains('username') -and $Recipe.username) {
        if ($Recipe.username -ne $Username) {
            return $false
        }
    }

    # A recipe's initial_mode must match the current system state.
    # On connect: enter-mobile (initial_mode=DESKTOP) matches when system is DESKTOP.
    # On disconnect: return-desktop (initial_mode=MOBILE) matches when system is MOBILE.
    if (-not [string]::IsNullOrEmpty($Recipe.initial_mode) -and $Recipe.initial_mode -ne $CurrentMode) {
        return $false
    }

    # The recipe must have a target_mode that differs from the current mode.
    # This prevents no-op dispatches and ensures connect vs disconnect recipes
    # don't match the wrong event type.
    # - Connect from DESKTOP: enter-mobile (target=MOBILE != DESKTOP) matches
    # - Disconnect from MOBILE: return-desktop (target=DESKTOP != MOBILE) matches
    # - Connect from DESKTOP: return-desktop (target=DESKTOP == DESKTOP) does NOT match
    if ([string]::IsNullOrEmpty($Recipe.target_mode)) {
        return $false
    }

    if ($Recipe.target_mode -eq $CurrentMode) {
        return $false
    }

    return $true
}

function Get-ParsecRecipeGracePeriod {
    [CmdletBinding()]
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
