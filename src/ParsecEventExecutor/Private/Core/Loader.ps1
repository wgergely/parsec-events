function Get-ParsecCorePrivateRoot {
    [CmdletBinding()]
    param()

    return Split-Path -Path $PSScriptRoot -Parent
}

function Get-ParsecCoreDomainRoot {
    [CmdletBinding()]
    param()

    return Join-Path -Path (Get-ParsecCorePrivateRoot) -ChildPath 'Domains'
}

function Get-ParsecCoreIngredientRoot {
    [CmdletBinding()]
    param()

    return Join-Path -Path (Get-ParsecCorePrivateRoot) -ChildPath 'Ingredients'
}

function Import-ParsecCoreDomainPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $DomainPath
    )

    $entryPath = Join-Path -Path $DomainPath -ChildPath 'entry.ps1'
    if (-not (Test-Path -LiteralPath $entryPath)) {
        throw "Domain package '$DomainPath' is missing entry.ps1."
    }

    $package = & $entryPath
    $plainPackage = ConvertTo-ParsecPlainObject -InputObject $package
    if ($plainPackage -isnot [System.Collections.IDictionary]) {
        throw "Domain package '$DomainPath' entry.ps1 must return a hashtable-like definition."
    }

    if (-not $plainPackage.Contains('Name') -or -not $plainPackage.Contains('Api')) {
        throw "Domain package '$DomainPath' must return Name and Api."
    }

    $definition = New-ParsecCoreDomainDefinition -Name ([string] $plainPackage.Name) -Api $plainPackage.Api -Description $(if ($plainPackage.Contains('Description')) { [string] $plainPackage.Description } else { '' }) -Metadata $(if ($plainPackage.Contains('Metadata')) { [System.Collections.IDictionary] $plainPackage.Metadata } else { @{} })
    Register-ParsecCoreDomain -Definition $definition | Out-Null
    return $definition
}

function Import-ParsecCoreIngredientPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $IngredientPath
    )

    $schemaPath = Join-Path -Path $IngredientPath -ChildPath 'schema.toml'
    $entryPath = Join-Path -Path $IngredientPath -ChildPath 'entry.ps1'
    if (-not (Test-Path -LiteralPath $schemaPath)) {
        throw "Ingredient package '$IngredientPath' is missing schema.toml."
    }
    if (-not (Test-Path -LiteralPath $entryPath)) {
        throw "Ingredient package '$IngredientPath' is missing entry.ps1."
    }

    $schema = ConvertFrom-ParsecToml -Path $schemaPath
    $packageFormat = 'entry'
    $package = & $entryPath -Schema $schema -IngredientPath $IngredientPath

    $plainPackage = ConvertTo-ParsecPlainObject -InputObject $package
    if ($plainPackage -isnot [System.Collections.IDictionary]) {
        throw "Ingredient package '$IngredientPath' entry.ps1 must return a hashtable-like definition."
    }

    if (-not $plainPackage.Contains('Operations')) {
        throw "Ingredient package '$IngredientPath' must return Operations."
    }

    $metadata = if ($plainPackage.Contains('Metadata') -and $plainPackage.Metadata -is [System.Collections.IDictionary]) {
        [ordered]@{} + (ConvertTo-ParsecPlainObject -InputObject $plainPackage.Metadata)
    }
    else {
        [ordered]@{}
    }

    if (-not $metadata.Contains('package_format')) {
        $metadata['package_format'] = $packageFormat
    }

    if (-not $metadata.Contains('ingredient_path')) {
        $metadata['ingredient_path'] = $IngredientPath
    }

    $plainPackage['Metadata'] = $metadata

    $definition = if ($plainPackage.Contains('Definition')) {
        $plainPackage.Definition
    }
    else {
        New-ParsecCoreIngredientDefinitionFromSchema -Schema $schema -Package $plainPackage -IngredientPath $IngredientPath
    }

    Register-ParsecCoreIngredient -Definition $definition | Out-Null
    return $definition
}

function Initialize-ParsecCoreRuntime {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch] $Force
    )

    Initialize-ParsecCoreRegistryState
    if ($Force) {
        Clear-ParsecCoreRegistryState
    }
    elseif ($script:ParsecCoreDomainRegistry.Count -gt 0 -or $script:ParsecCoreIngredientRegistry.Count -gt 0) {
        return
    }

    $domainRoot = Get-ParsecCoreDomainRoot
    if (Test-Path -LiteralPath $domainRoot) {
        foreach ($directory in Get-ChildItem -LiteralPath $domainRoot -Directory | Sort-Object Name) {
            Import-ParsecCoreDomainPackage -DomainPath $directory.FullName | Out-Null
        }
    }

    $ingredientRoot = Get-ParsecCoreIngredientRoot
    if (Test-Path -LiteralPath $ingredientRoot) {
        foreach ($directory in Get-ChildItem -LiteralPath $ingredientRoot -Directory | Sort-Object Name) {
            Import-ParsecCoreIngredientPackage -IngredientPath $directory.FullName | Out-Null
        }
    }
}
