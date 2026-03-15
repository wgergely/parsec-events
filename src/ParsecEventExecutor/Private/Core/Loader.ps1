function Get-ParsecCorePrivateRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return Split-Path -Path $PSScriptRoot -Parent
}

function Get-ParsecCoreDomainRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return Join-Path -Path (Get-ParsecCorePrivateRoot) -ChildPath 'Domains'
}

function Get-ParsecCoreIngredientRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return Join-Path -Path (Get-ParsecCorePrivateRoot) -ChildPath 'Ingredients'
}

function ConvertTo-ParsecCorePackageMap {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        $InputObject
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        return [ordered]@{} + $InputObject
    }

    if ($InputObject -is [psobject] -and $null -ne $InputObject.PSObject) {
        $output = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            if ($property.Name -in @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')) {
                continue
            }

            $output[$property.Name] = $property.Value
        }

        return $output
    }

    throw 'Package entrypoint must return a hashtable-like definition.'
}

function Import-ParsecCoreDomainPackage {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string] $DomainPath
    )

    $entryPath = Join-Path -Path $DomainPath -ChildPath 'entry.ps1'
    if (-not (Test-Path -LiteralPath $entryPath)) {
        throw "Domain package '$DomainPath' is missing entry.ps1."
    }

    . (Join-Path -Path $PSScriptRoot -ChildPath 'HostSupport.ps1')
    $module = $ExecutionContext.SessionState.Module
    if ($null -ne $module) {
        $package = & $module {
            param($path)
            . $path
        } $entryPath
    }
    else {
        $package = . $entryPath
    }
    $plainPackage = ConvertTo-ParsecCorePackageMap -InputObject $package

    if (-not $plainPackage.Contains('Name') -or -not $plainPackage.Contains('Api')) {
        throw "Domain package '$DomainPath' must return Name and Api."
    }

    $definition = New-ParsecCoreDomainDefinition -Name ([string] $plainPackage.Name) -Api $plainPackage.Api -Description $(if ($plainPackage.Contains('Description')) { [string] $plainPackage.Description } else { '' }) -Metadata $(if ($plainPackage.Contains('Metadata')) { [System.Collections.IDictionary] $plainPackage.Metadata } else { @{} })
    Register-ParsecCoreDomain -Definition $definition | Out-Null
    return $definition
}

function Import-ParsecCoreDomainPackageByName {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    Initialize-ParsecCoreRegistryState
    if ($script:ParsecCoreDomainRegistry.ContainsKey($Name)) {
        return $script:ParsecCoreDomainRegistry[$Name]
    }

    if (-not $script:ParsecCoreDomainCatalog.ContainsKey($Name)) {
        throw "Domain '$Name' is not cataloged."
    }

    return Import-ParsecCoreDomainPackage -DomainPath ([string] $script:ParsecCoreDomainCatalog[$Name].DomainPath)
}

function Import-ParsecCoreIngredientPackage {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
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

    . (Join-Path -Path $PSScriptRoot -ChildPath 'HostSupport.ps1')
    $schema = ConvertFrom-ParsecToml -Path $schemaPath
    $packageFormat = 'entry'
    $module = $ExecutionContext.SessionState.Module
    if ($null -ne $module) {
        $package = & $module {
            param($path, $innerSchema, $innerIngredientPath)
            & $path -Schema $innerSchema -IngredientPath $innerIngredientPath
        } $entryPath $schema $IngredientPath
    }
    else {
        $package = & $entryPath -Schema $schema -IngredientPath $IngredientPath
    }
    $plainPackage = ConvertTo-ParsecCorePackageMap -InputObject $package

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

function Import-ParsecCoreIngredientPackageByName {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    Initialize-ParsecCoreRegistryState
    if ($script:ParsecCoreIngredientRegistry.ContainsKey($Name)) {
        return $script:ParsecCoreIngredientRegistry[$Name]
    }

    if (-not $script:ParsecCoreIngredientCatalog.ContainsKey($Name)) {
        throw "Ingredient '$Name' is not cataloged."
    }

    $catalogDefinition = $script:ParsecCoreIngredientCatalog[$Name]
    return Import-ParsecCoreIngredientPackage -IngredientPath ([string] $catalogDefinition.Metadata.ingredient_path)
}

function Get-ParsecCoreIngredientCatalogDefinition {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Schema,

        [Parameter(Mandatory)]
        [string] $IngredientPath
    )

    $metadata = [ordered]@{
        package_format = 'entry'
        ingredient_path = $IngredientPath
        schema_path = Join-Path -Path $IngredientPath -ChildPath 'schema.toml'
        entry_path = Join-Path -Path $IngredientPath -ChildPath 'entry.ps1'
        load_state = 'catalog'
    }

    $operationSchemas = [ordered]@{}
    if ($Schema.Contains('operation_schemas')) {
        foreach ($operationName in @($Schema.operation_schemas.Keys)) {
            $operationSchemas[$operationName] = ConvertTo-ParsecPlainObject -InputObject $Schema.operation_schemas[$operationName]
        }
    }

    $domain = Get-ParsecCoreRequiredIngredientDomain -Schema $Schema

    return New-ParsecCoreIngredientDefinition `
        -Name ([string] $Schema.name) `
        -Domain $domain `
        -Kind ([string] $Schema.kind) `
        -Description $(if ($Schema.Contains('description')) { [string] $Schema.description } else { '' }) `
        -Aliases $(if ($Schema.Contains('aliases')) { @($Schema.aliases) } else { @() }) `
        -Capabilities $(if ($Schema.Contains('capabilities')) { @($Schema.capabilities) } else { @() }) `
        -RequiredCapabilities $(if ($Schema.Contains('required_capabilities')) { @($Schema.required_capabilities) } else { @() }) `
        -OperationSchemas $operationSchemas `
        -SafetyClass $(if ($Schema.Contains('safety_class')) { [string] $Schema.safety_class } else { 'ReadOnly' }) `
        -SuccessSignals $(if ($Schema.Contains('success_signals')) { @($Schema.success_signals) } else { @() }) `
        -FailureSignals $(if ($Schema.Contains('failure_signals')) { @($Schema.failure_signals) } else { @() }) `
        -WaitConditions $(if ($Schema.Contains('wait_conditions')) { @($Schema.wait_conditions) } else { @() }) `
        -Readiness $(if ($Schema.Contains('readiness')) { [System.Collections.IDictionary] (ConvertTo-ParsecPlainObject -InputObject $Schema.readiness) } else { @{} }) `
        -Operations @{} `
        -Metadata $metadata
}

function Resolve-ParsecCoreIngredientCatalogEntry {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    Initialize-ParsecCoreRegistryState

    $normalizedFolderName = ($Name -replace '\.', '-')
    if ($script:ParsecCoreIngredientPathCatalog.ContainsKey($normalizedFolderName)) {
        $candidatePath = [string] $script:ParsecCoreIngredientPathCatalog[$normalizedFolderName].IngredientPath
        $schema = ConvertFrom-ParsecToml -Path (Join-Path -Path $candidatePath -ChildPath 'schema.toml')
        $catalogDefinition = Get-ParsecCoreIngredientCatalogDefinition -Schema $schema -IngredientPath $candidatePath
        Register-ParsecCoreIngredientCatalogEntry -Definition $catalogDefinition | Out-Null
        if ($catalogDefinition.Name -eq $Name -or @($catalogDefinition.Aliases) -contains $Name) {
            return $catalogDefinition
        }
    }

    foreach ($entry in @($script:ParsecCoreIngredientPathCatalog.Values)) {
        $candidatePath = [string] $entry.IngredientPath
        if (@($script:ParsecCoreIngredientCatalog.Values | Where-Object { $_.Metadata.ingredient_path -eq $candidatePath }).Count -gt 0) {
            continue
        }

        $schema = ConvertFrom-ParsecToml -Path (Join-Path -Path $candidatePath -ChildPath 'schema.toml')
        $catalogDefinition = Get-ParsecCoreIngredientCatalogDefinition -Schema $schema -IngredientPath $candidatePath
        Register-ParsecCoreIngredientCatalogEntry -Definition $catalogDefinition | Out-Null
        if ($catalogDefinition.Name -eq $Name -or @($catalogDefinition.Aliases) -contains $Name) {
            return $catalogDefinition
        }
    }

    return $null
}

function Import-ParsecCoreIngredientCatalog {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    Initialize-ParsecCoreRegistryState
    foreach ($entry in @($script:ParsecCoreIngredientPathCatalog.Values | Sort-Object FolderName)) {
        $candidatePath = [string] $entry.IngredientPath
        if (@($script:ParsecCoreIngredientCatalog.Values | Where-Object { $_.Metadata.ingredient_path -eq $candidatePath }).Count -gt 0) {
            continue
        }

        $schema = ConvertFrom-ParsecToml -Path (Join-Path -Path $candidatePath -ChildPath 'schema.toml')
        $catalogDefinition = Get-ParsecCoreIngredientCatalogDefinition -Schema $schema -IngredientPath $candidatePath
        Register-ParsecCoreIngredientCatalogEntry -Definition $catalogDefinition | Out-Null
    }
}

function Initialize-ParsecCoreRuntime {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [switch] $Force
    )

    Initialize-ParsecCoreRegistryState
    if ($Force) {
        Clear-ParsecCoreRegistryState
    }
    elseif ($script:ParsecCoreDomainCatalog.Count -gt 0 -or $script:ParsecCoreIngredientCatalog.Count -gt 0) {
        return
    }

    $domainRoot = Get-ParsecCoreDomainRoot
    if (Test-Path -LiteralPath $domainRoot) {
        foreach ($directory in Get-ChildItem -LiteralPath $domainRoot -Directory | Sort-Object Name) {
            Register-ParsecCoreDomainCatalogEntry -Name ([string] $directory.Name) -DomainPath $directory.FullName | Out-Null
        }
    }

    $ingredientRoot = Get-ParsecCoreIngredientRoot
    if (Test-Path -LiteralPath $ingredientRoot) {
        foreach ($directory in Get-ChildItem -LiteralPath $ingredientRoot -Directory | Sort-Object Name) {
            Register-ParsecCoreIngredientPathCatalogEntry -FolderName ([string] $directory.Name) -IngredientPath $directory.FullName
        }
    }
}
