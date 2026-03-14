function New-ParsecCoreLoggerProxy {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Debug = {
            param([string] $Message)
            Write-Verbose $Message
        }
        Info = {
            param([string] $Message)
            Write-Information $Message -InformationAction Continue
        }
        Warn = {
            param([string] $Message)
            Write-Warning $Message
        }
        Error = {
            param([string] $Message)
            Write-Error $Message
        }
    }
}

function New-ParsecCoreResultProxy {
    [CmdletBinding()]
    param()

    return [pscustomobject]@{
        Create = {
            param(
                [string] $Status,
                [string] $Message,
                [System.Collections.IDictionary] $Requested,
                [System.Collections.IDictionary] $Observed,
                [System.Collections.IDictionary] $Outputs,
                [string[]] $Warnings,
                [string[]] $Errors,
                [bool] $CanCompensate
            )

            $requestedValue = if ($null -ne $Requested) { $Requested } else { @{} }
            $observedValue = if ($null -ne $Observed) { $Observed } else { @{} }
            $outputsValue = if ($null -ne $Outputs) { $Outputs } else { @{} }
            $warningsValue = if ($null -ne $Warnings) { $Warnings } else { @() }
            $errorsValue = if ($null -ne $Errors) { $Errors } else { @() }

            return New-ParsecResult -Status $Status -Message $Message -Requested $requestedValue -Observed $observedValue -Outputs $outputsValue -Warnings $warningsValue -Errors $errorsValue -CanCompensate $CanCompensate
        }
        Succeed = {
            param(
                [string] $Message,
                [System.Collections.IDictionary] $Observed,
                [System.Collections.IDictionary] $Outputs
            )

            return New-ParsecResult -Status 'Succeeded' -Message $Message -Observed $(if ($null -ne $Observed) { $Observed } else { @{} }) -Outputs $(if ($null -ne $Outputs) { $Outputs } else { @{} })
        }
        Fail = {
            param(
                [string] $Message,
                [System.Collections.IDictionary] $Observed,
                [System.Collections.IDictionary] $Outputs,
                [string[]] $Errors
            )

            return New-ParsecResult -Status 'Failed' -Message $Message -Observed $(if ($null -ne $Observed) { $Observed } else { @{} }) -Outputs $(if ($null -ne $Outputs) { $Outputs } else { @{} }) -Errors $(if ($null -ne $Errors) { $Errors } else { @() })
        }
        Drift = {
            param(
                [string] $Message,
                [System.Collections.IDictionary] $Observed,
                [System.Collections.IDictionary] $Outputs
            )

            return New-ParsecResult -Status 'SucceededWithDrift' -Message $Message -Observed $(if ($null -ne $Observed) { $Observed } else { @{} }) -Outputs $(if ($null -ne $Outputs) { $Outputs } else { @{} })
        }
    }
}

function New-ParsecCorePersistenceProxy {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    return [pscustomobject]@{
        StateRoot = $StateRoot
        DefaultStateRoot = { return Get-ParsecDefaultStateRoot }
        Initialize = { param([string] $TargetStateRoot) return Initialize-ParsecStateRoot -StateRoot $TargetStateRoot }
        ReadDocument = { param([string] $Path, [string] $ExpectedType) return Read-ParsecStateDocument -Path $Path -ExpectedDocumentType $ExpectedType }
        WriteDocument = { param([string] $Path, [string] $DocumentType, $Payload) return Write-ParsecStateDocument -Path $Path -DocumentType $DocumentType -Payload $Payload }
        ReadJson = { param([string] $Path) return Read-ParsecJsonFile -Path $Path }
        WriteJson = { param([string] $Path, $InputObject) return Write-ParsecJsonFile -Path $Path -InputObject $InputObject }
    }
}

function New-ParsecCoreExecutionContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $IngredientDefinition,

        [Parameter(Mandatory)]
        $DomainDefinition,

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

    $domainApis = [ordered]@{
        $DomainDefinition.Name = $DomainDefinition.Api
    }

    return [pscustomobject]@{
        Ingredient = $IngredientDefinition
        Domain = $DomainDefinition
        DomainApi = $DomainDefinition.Api
        Domains = [pscustomobject] $domainApis
        Arguments = ConvertTo-ParsecPlainObject -InputObject $Arguments
        Prior = ConvertTo-ParsecPlainObject -InputObject $Prior
        StateRoot = $StateRoot
        RunState = $RunState
        Metadata = ConvertTo-ParsecPlainObject -InputObject $Metadata
        Logger = New-ParsecCoreLoggerProxy
        Results = New-ParsecCoreResultProxy
        Persistence = New-ParsecCorePersistenceProxy -StateRoot $StateRoot
    }
}
