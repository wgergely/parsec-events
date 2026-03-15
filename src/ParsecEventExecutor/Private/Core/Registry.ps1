function Initialize-ParsecCoreRegistryState {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not (Get-Variable -Name ParsecCoreDomainCatalog -Scope Script -ErrorAction SilentlyContinue)) {
        $script:ParsecCoreDomainCatalog = @{}
    }

    if (-not (Get-Variable -Name ParsecCoreDomainRegistry -Scope Script -ErrorAction SilentlyContinue)) {
        $script:ParsecCoreDomainRegistry = @{}
    }

    if (-not (Get-Variable -Name ParsecCoreIngredientCatalog -Scope Script -ErrorAction SilentlyContinue)) {
        $script:ParsecCoreIngredientCatalog = @{}
    }

    if (-not (Get-Variable -Name ParsecCoreIngredientPathCatalog -Scope Script -ErrorAction SilentlyContinue)) {
        $script:ParsecCoreIngredientPathCatalog = @{}
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
    [OutputType([void])]
    param()

    Initialize-ParsecCoreRegistryState
    $script:ParsecCoreDomainCatalog = @{}
    $script:ParsecCoreDomainRegistry = @{}
    $script:ParsecCoreIngredientCatalog = @{}
    $script:ParsecCoreIngredientPathCatalog = @{}
    $script:ParsecCoreIngredientRegistry = @{}
    $script:ParsecCoreIngredientAliasRegistry = @{}
}

function Register-ParsecCoreDomainCatalogEntry {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $DomainPath
    )

    Initialize-ParsecCoreRegistryState
    if ($PSCmdlet.ShouldProcess("Domain catalog entry '$Name'", 'Register')) {
        $script:ParsecCoreDomainCatalog[$Name] = [pscustomobject]@{
            Name = $Name
            DomainPath = $DomainPath
            EntryPath = Join-Path -Path $DomainPath -ChildPath 'entry.ps1'
        }
    }
}

function Register-ParsecCoreDomain {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        $Definition
    )

    Initialize-ParsecCoreRegistryState
    if ($script:ParsecCoreDomainRegistry.ContainsKey($Definition.Name)) {
        throw "Domain '$($Definition.Name)' is already registered."
    }

    if ($PSCmdlet.ShouldProcess("Domain '$($Definition.Name)'", 'Register')) {
        $script:ParsecCoreDomainRegistry[$Definition.Name] = $Definition
    }
    return $Definition
}

function Get-ParsecCoreDomainDefinition {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    Initialize-ParsecCoreRegistryState
    if (-not $script:ParsecCoreDomainRegistry.ContainsKey($Name)) {
        Import-ParsecCoreDomainPackageByName -Name $Name | Out-Null
    }

    if (-not $script:ParsecCoreDomainRegistry.ContainsKey($Name)) {
        throw "Domain '$Name' is not registered."
    }

    return $script:ParsecCoreDomainRegistry[$Name]
}

function Get-ParsecCoreDomainApi {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    return (Get-ParsecCoreDomainDefinition -Name $Name).Api
}

function Register-ParsecCoreIngredient {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        $Definition
    )

    Initialize-ParsecCoreRegistryState
    if (-not $script:ParsecCoreDomainRegistry.ContainsKey($Definition.Domain)) {
        Get-ParsecCoreDomainDefinition -Name $Definition.Domain | Out-Null
    }

    if (-not $script:ParsecCoreDomainRegistry.ContainsKey($Definition.Domain)) {
        throw "Ingredient '$($Definition.Name)' declares unknown domain '$($Definition.Domain)'."
    }

    if ($script:ParsecCoreIngredientRegistry.ContainsKey($Definition.Name)) {
        throw "Ingredient '$($Definition.Name)' is already registered."
    }

    if ($PSCmdlet.ShouldProcess("Ingredient '$($Definition.Name)'", 'Register')) {
        $script:ParsecCoreIngredientRegistry[$Definition.Name] = $Definition
        foreach ($alias in @($Definition.Aliases)) {
            if ([string]::IsNullOrWhiteSpace([string] $alias)) {
                continue
            }

            if ($script:ParsecCoreIngredientAliasRegistry.ContainsKey([string] $alias)) {
                if ([string] $script:ParsecCoreIngredientAliasRegistry[[string] $alias] -eq [string] $Definition.Name) {
                    continue
                }

                throw "Ingredient alias '$alias' is already registered."
            }

            $script:ParsecCoreIngredientAliasRegistry[[string] $alias] = $Definition.Name
        }
    }

    return $Definition
}

function Register-ParsecCoreIngredientCatalogEntry {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        $Definition
    )

    Initialize-ParsecCoreRegistryState
    if ($PSCmdlet.ShouldProcess("Ingredient catalog entry '$($Definition.Name)'", 'Register')) {
        $script:ParsecCoreIngredientCatalog[$Definition.Name] = $Definition
        foreach ($alias in @($Definition.Aliases)) {
            if ([string]::IsNullOrWhiteSpace([string] $alias)) {
                continue
            }

            if (
                $script:ParsecCoreIngredientAliasRegistry.ContainsKey([string] $alias) -and
                [string] $script:ParsecCoreIngredientAliasRegistry[[string] $alias] -ne [string] $Definition.Name
            ) {
                throw "Ingredient alias '$alias' is already registered."
            }

            $script:ParsecCoreIngredientAliasRegistry[[string] $alias] = $Definition.Name
        }
    }

    return $Definition
}

function Register-ParsecCoreIngredientPathCatalogEntry {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $FolderName,

        [Parameter(Mandatory)]
        [string] $IngredientPath
    )

    Initialize-ParsecCoreRegistryState
    if ($PSCmdlet.ShouldProcess("Ingredient path catalog entry '$FolderName'", 'Register')) {
        $script:ParsecCoreIngredientPathCatalog[$FolderName] = [pscustomobject]@{
            FolderName = $FolderName
            IngredientPath = $IngredientPath
        }
    }
}

function Resolve-ParsecCoreIngredientName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    Initialize-ParsecCoreRegistryState
    if ($script:ParsecCoreIngredientRegistry.ContainsKey($Name)) {
        return $Name
    }

    if ($script:ParsecCoreIngredientCatalog.ContainsKey($Name)) {
        return $Name
    }

    if ($script:ParsecCoreIngredientAliasRegistry.ContainsKey($Name)) {
        return [string] $script:ParsecCoreIngredientAliasRegistry[$Name]
    }

    Resolve-ParsecCoreIngredientCatalogEntry -Name $Name | Out-Null

    if ($script:ParsecCoreIngredientCatalog.ContainsKey($Name)) {
        return $Name
    }

    if ($script:ParsecCoreIngredientAliasRegistry.ContainsKey($Name)) {
        return [string] $script:ParsecCoreIngredientAliasRegistry[$Name]
    }

    throw "Ingredient '$Name' is not registered."
}

function Get-ParsecCoreIngredientDefinition {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $resolvedName = Resolve-ParsecCoreIngredientName -Name $Name
    if (-not $script:ParsecCoreIngredientRegistry.ContainsKey($resolvedName)) {
        Import-ParsecCoreIngredientPackageByName -Name $resolvedName | Out-Null
    }
    return $script:ParsecCoreIngredientRegistry[$resolvedName]
}

function Get-ParsecCoreIngredientDefinitions {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    [OutputType([System.Object[]])]
    param()

    Initialize-ParsecCoreRegistryState
    if ($script:ParsecCoreIngredientCatalog.Count -lt $script:ParsecCoreIngredientPathCatalog.Count) {
        Import-ParsecCoreIngredientCatalog | Out-Null
    }
    return @($script:ParsecCoreIngredientCatalog.Values | Sort-Object Name)
}
