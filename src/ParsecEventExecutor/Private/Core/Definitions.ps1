function New-ParsecCoreDomainDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        $Api,

        [Parameter()]
        [string] $Description = '',

        [Parameter()]
        [System.Collections.IDictionary] $Metadata = @{}
    )

    return [pscustomobject]@{
        PSTypeName = 'ParsecEventExecutor.DomainDefinition'
        Name = $Name
        Description = $Description
        Api = $Api
        Metadata = ConvertTo-ParsecPlainObject -InputObject $Metadata
    }
}

function New-ParsecCoreIngredientDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Domain,

        [Parameter(Mandatory)]
        [string] $Kind,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Operations,

        [Parameter()]
        [string] $Description = '',

        [Parameter()]
        [string[]] $Aliases = @(),

        [Parameter()]
        [string[]] $Capabilities = @(),

        [Parameter()]
        [string[]] $RequiredCapabilities = @(),

        [Parameter()]
        [System.Collections.IDictionary] $OperationSchemas = @{},

        [Parameter()]
        [string] $SafetyClass = 'ReadOnly',

        [Parameter()]
        [string[]] $SuccessSignals = @(),

        [Parameter()]
        [string[]] $FailureSignals = @(),

        [Parameter()]
        [string[]] $WaitConditions = @(),

        [Parameter()]
        [System.Collections.IDictionary] $Readiness = @{},

        [Parameter()]
        [System.Collections.IDictionary] $Metadata = @{}
    )

    return [pscustomobject]@{
        PSTypeName = 'ParsecEventExecutor.IngredientDefinition'
        Name = $Name
        Domain = $Domain
        Kind = $Kind
        Description = $Description
        Aliases = @($Aliases)
        Capabilities = @($Capabilities)
        RequiredCapabilities = @($RequiredCapabilities)
        OperationSchemas = ConvertTo-ParsecPlainObject -InputObject $OperationSchemas
        Operations = $Operations
        SafetyClass = $SafetyClass
        SuccessSignals = @($SuccessSignals)
        FailureSignals = @($FailureSignals)
        WaitConditions = @($WaitConditions)
        Readiness = ConvertTo-ParsecPlainObject -InputObject $Readiness
        Metadata = ConvertTo-ParsecPlainObject -InputObject $Metadata
    }
}

function New-ParsecCoreIngredientDefinitionFromSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Schema,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Package,

        [Parameter()]
        [string] $IngredientPath
    )

    $operationSchemas = [ordered]@{}
    if ($Schema.Contains('operation_schemas')) {
        foreach ($operationName in @($Schema.operation_schemas.Keys)) {
            $operationSchemas[$operationName] = ConvertTo-ParsecPlainObject -InputObject $Schema.operation_schemas[$operationName]
        }
    }

    $domain = if ($Schema.Contains('domain')) {
        [string] $Schema.domain
    }
    elseif ($Package.Contains('Domain')) {
        [string] $Package.Domain
    }
    else {
        Resolve-ParsecCoreIngredientDomain -Name ([string] $Schema.name)
    }

    $requiredCapabilities = if ($Schema.Contains('required_capabilities')) {
        @($Schema.required_capabilities)
    }
    elseif ($Package.Contains('RequiredCapabilities')) {
        @($Package.RequiredCapabilities)
    }
    else {
        @()
    }

    return New-ParsecCoreIngredientDefinition `
        -Name ([string] $Schema.name) `
        -Domain $domain `
        -Kind ([string] $Schema.kind) `
        -Description $(if ($Schema.Contains('description')) { [string] $Schema.description } else { '' }) `
        -Aliases $(if ($Schema.Contains('aliases')) { @($Schema.aliases) } else { @() }) `
        -Capabilities $(if ($Schema.Contains('capabilities')) { @($Schema.capabilities) } else { @() }) `
        -RequiredCapabilities $requiredCapabilities `
        -OperationSchemas $operationSchemas `
        -SafetyClass $(if ($Schema.Contains('safety_class')) { [string] $Schema.safety_class } else { 'ReadOnly' }) `
        -SuccessSignals $(if ($Schema.Contains('success_signals')) { @($Schema.success_signals) } else { @() }) `
        -FailureSignals $(if ($Schema.Contains('failure_signals')) { @($Schema.failure_signals) } else { @() }) `
        -WaitConditions $(if ($Schema.Contains('wait_conditions')) { @($Schema.wait_conditions) } else { @() }) `
        -Readiness $(if ($Schema.Contains('readiness')) { [System.Collections.IDictionary] (ConvertTo-ParsecPlainObject -InputObject $Schema.readiness) } else { @{} }) `
        -Operations $Package.Operations `
        -Metadata $(if ($Package.Contains('Metadata')) { [System.Collections.IDictionary] (ConvertTo-ParsecPlainObject -InputObject $Package.Metadata) } else { @{} })
}

function Resolve-ParsecCoreIngredientDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    switch -Regex ($Name) {
        '^display\.' { return 'display' }
        '^process\.' { return 'process' }
        '^service\.' { return 'service' }
        '^nvidia\.' { return 'nvidia' }
        '^window\.' { return 'window' }
        '^command\.' { return 'command' }
        '^system\.set-theme$' { return 'personalization' }
        default {
            throw "Ingredient '$Name' is missing required 'domain' metadata and no domain could be inferred."
        }
    }
}
