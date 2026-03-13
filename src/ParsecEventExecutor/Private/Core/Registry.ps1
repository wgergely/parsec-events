function Initialize-ParsecCoreRegistryState {
    [CmdletBinding()]
    param()

    if (-not (Get-Variable -Name ParsecCoreDomainRegistry -Scope Script -ErrorAction SilentlyContinue)) {
        $script:ParsecCoreDomainRegistry = @{}
    }

    if (-not (Get-Variable -Name ParsecCoreIngredientRegistry -Scope Script -ErrorAction SilentlyContinue)) {
        $script:ParsecCoreIngredientRegistry = @{}
    }

    if (-not (Get-Variable -Name ParsecCoreIngredientAliasRegistry -Scope Script -ErrorAction SilentlyContinue)) {
        $script:ParsecCoreIngredientAliasRegistry = @{}
    }
}

function Clear-ParsecCoreRegistryState {
    [CmdletBinding()]
    param()

    Initialize-ParsecCoreRegistryState
    $script:ParsecCoreDomainRegistry = @{}
    $script:ParsecCoreIngredientRegistry = @{}
    $script:ParsecCoreIngredientAliasRegistry = @{}
}

function Register-ParsecCoreDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Definition
    )

    Initialize-ParsecCoreRegistryState
    if ($script:ParsecCoreDomainRegistry.ContainsKey($Definition.Name)) {
        throw "Domain '$($Definition.Name)' is already registered."
    }

    $script:ParsecCoreDomainRegistry[$Definition.Name] = $Definition
    return $Definition
}

function Get-ParsecCoreDomainDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    Initialize-ParsecCoreRegistryState
    if (-not $script:ParsecCoreDomainRegistry.ContainsKey($Name)) {
        throw "Domain '$Name' is not registered."
    }

    return $script:ParsecCoreDomainRegistry[$Name]
}

function Get-ParsecCoreDomainApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    return (Get-ParsecCoreDomainDefinition -Name $Name).Api
}

function Register-ParsecCoreIngredient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Definition
    )

    Initialize-ParsecCoreRegistryState
    if (-not $script:ParsecCoreDomainRegistry.ContainsKey($Definition.Domain)) {
        throw "Ingredient '$($Definition.Name)' declares unknown domain '$($Definition.Domain)'."
    }

    if ($script:ParsecCoreIngredientRegistry.ContainsKey($Definition.Name)) {
        throw "Ingredient '$($Definition.Name)' is already registered."
    }

    $script:ParsecCoreIngredientRegistry[$Definition.Name] = $Definition
    foreach ($alias in @($Definition.Aliases)) {
        if ([string]::IsNullOrWhiteSpace([string] $alias)) {
            continue
        }

        if ($script:ParsecCoreIngredientAliasRegistry.ContainsKey([string] $alias)) {
            throw "Ingredient alias '$alias' is already registered."
        }

        $script:ParsecCoreIngredientAliasRegistry[[string] $alias] = $Definition.Name
    }

    return $Definition
}

function Resolve-ParsecCoreIngredientName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    Initialize-ParsecCoreRegistryState
    if ($script:ParsecCoreIngredientRegistry.ContainsKey($Name)) {
        return $Name
    }

    if ($script:ParsecCoreIngredientAliasRegistry.ContainsKey($Name)) {
        return [string] $script:ParsecCoreIngredientAliasRegistry[$Name]
    }

    throw "Ingredient '$Name' is not registered."
}

function Get-ParsecCoreIngredientDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $resolvedName = Resolve-ParsecCoreIngredientName -Name $Name
    return $script:ParsecCoreIngredientRegistry[$resolvedName]
}

function Get-ParsecCoreIngredientDefinitions {
    [CmdletBinding()]
    param()

    Initialize-ParsecCoreRegistryState
    return @($script:ParsecCoreIngredientRegistry.Values | Sort-Object Name)
}
