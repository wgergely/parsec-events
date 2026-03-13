function Initialize-ParsecIngredientRegistry {
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch] $Force
    )

    Initialize-ParsecCoreRuntime -Force:$Force
    $script:ParsecIngredientRegistry = $script:ParsecCoreIngredientRegistry
    $script:ParsecIngredientAliasRegistry = $script:ParsecCoreIngredientAliasRegistry
}

function Resolve-ParsecIngredientName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    return Resolve-ParsecCoreIngredientName -Name $Name
}

function Get-ParsecIngredientDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    return Get-ParsecCoreIngredientDefinition -Name $Name
}

function Test-ParsecIngredientOperationSupported {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Definition,

        [Parameter(Mandatory)]
        [string] $Operation
    )

    return Test-ParsecCoreIngredientOperationSupported -Definition $Definition -Operation $Operation
}

function Invoke-ParsecIngredientOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Operation,

        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{}
    )

    return Invoke-ParsecCoreIngredientOperation -Name $Name -Operation $Operation -Arguments $Arguments -Prior $ExecutionResult -StateRoot $StateRoot -RunState $RunState
}

function Invoke-ParsecIngredientExecute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{}
    )

    return Invoke-ParsecCoreIngredientExecute -Name $Name -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState
}

function Invoke-ParsecIngredientVerify {
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

    return Invoke-ParsecCoreIngredientVerify -Name $Name -Arguments $Arguments -Prior $ExecutionResult -StateRoot $StateRoot -RunState $RunState
}

function Invoke-ParsecIngredientCompensate {
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

    return Invoke-ParsecCoreIngredientCompensate -Name $Name -Arguments $Arguments -Prior $ExecutionResult -StateRoot $StateRoot -RunState $RunState
}
