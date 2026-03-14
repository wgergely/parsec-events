function Test-ParsecCoreIngredientOperationSupported {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Definition,

        [Parameter(Mandatory)]
        [string] $Operation
    )

    if ($null -eq $Definition.Operations) {
        return $false
    }

    if ($Definition.Operations -is [System.Collections.IDictionary]) {
        if ($Definition.Operations -is [hashtable]) {
            return $Definition.Operations.ContainsKey($Operation)
        }

        return $Definition.Operations.Contains($Operation)
    }

    return $false
}

function Invoke-ParsecCoreIngredientOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Operation,

        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $Prior,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{},

        [Parameter()]
        [System.Collections.IDictionary] $Metadata = @{}
    )

    $definition = Get-ParsecCoreIngredientDefinition -Name $Name
    if (-not (Test-ParsecCoreIngredientOperationSupported -Definition $definition -Operation $Operation)) {
        throw "Ingredient '$Name' does not support operation '$Operation'."
    }

    Assert-ParsecCoreIngredientArguments -Definition $definition -Operation $Operation -Arguments $Arguments
    $domain = Get-ParsecCoreDomainDefinition -Name $definition.Domain
    $context = New-ParsecCoreExecutionContext -IngredientDefinition $definition -DomainDefinition $domain -Arguments $Arguments -Prior $Prior -StateRoot $StateRoot -RunState $RunState -Metadata $Metadata
    $handler = $definition.Operations[$Operation]
    return & $handler $context (ConvertTo-ParsecPlainObject -InputObject $Arguments) $Prior
}

function Invoke-ParsecCoreIngredientExecute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{},

        [Parameter()]
        [System.Collections.IDictionary] $Metadata = @{}
    )

    return Invoke-ParsecCoreIngredientOperation -Name $Name -Operation 'apply' -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState -Metadata $Metadata
}

function Invoke-ParsecCoreIngredientVerify {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $Prior,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{},

        [Parameter()]
        [System.Collections.IDictionary] $Metadata = @{}
    )

    $definition = Get-ParsecCoreIngredientDefinition -Name $Name
    if (-not (Test-ParsecCoreIngredientOperationSupported -Definition $definition -Operation 'verify')) {
        return $null
    }

    return Invoke-ParsecCoreIngredientOperation -Name $Name -Operation 'verify' -Arguments $Arguments -Prior $Prior -StateRoot $StateRoot -RunState $RunState -Metadata $Metadata
}

function Invoke-ParsecCoreIngredientCompensate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $Prior,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{},

        [Parameter()]
        [System.Collections.IDictionary] $Metadata = @{}
    )

    $definition = Get-ParsecCoreIngredientDefinition -Name $Name
    if (-not (Test-ParsecCoreIngredientOperationSupported -Definition $definition -Operation 'reset')) {
        return $null
    }

    return Invoke-ParsecCoreIngredientOperation -Name $Name -Operation 'reset' -Arguments $Arguments -Prior $Prior -StateRoot $StateRoot -RunState $RunState -Metadata $Metadata
}
