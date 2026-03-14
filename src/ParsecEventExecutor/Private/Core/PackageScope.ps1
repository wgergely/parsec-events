function Import-ParsecCorePackageSupportFiles {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]] $SupportFiles = @()
    )

    $validFiles = @(
        foreach ($file in @($SupportFiles)) {
            if (-not [string]::IsNullOrWhiteSpace([string] $file)) {
                [string] $file
            }
        }
    )

    $module = $ExecutionContext.SessionState.Module
    if ($null -ne $module) {
        & $module {
            param($Files)

            foreach ($file in @($Files)) {
                . $file
            }
        } $validFiles
        return
    }

    foreach ($file in @($validFiles)) {
        . $file
    }
}

function Invoke-ParsecCorePackageOperation {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]] $SupportFiles = @(),

        [Parameter(Mandatory)]
        [scriptblock] $Body,

        [Parameter()]
        [object[]] $ArgumentList = @()
    )

    $operationScope = {
        param($Files, $OperationBody, $OperationArguments)

        Import-ParsecCorePackageSupportFiles -SupportFiles $Files

        . $OperationBody @OperationArguments
    }

    return & $operationScope $SupportFiles $Body $ArgumentList
}
