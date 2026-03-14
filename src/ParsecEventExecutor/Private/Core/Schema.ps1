function Test-ParsecCoreArgumentType {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        $Value,

        [Parameter(Mandatory)]
        [string] $TypeName
    )

    switch ($TypeName) {
        'string' { return $Value -is [string] }
        'boolean' { return $Value -is [bool] }
        'integer' {
            return (
                $Value -is [int16] -or
                $Value -is [int32] -or
                $Value -is [int64] -or
                $Value -is [uint16] -or
                $Value -is [uint32] -or
                $Value -is [uint64]
            )
        }
        'array' { return $Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] }
        'hashtable' { return $Value -is [System.Collections.IDictionary] }
        'object' { return $Value -is [psobject] -or $Value -is [System.Collections.IDictionary] }
        default { return $true }
    }
}

function Get-ParsecCoreIngredientSchemaForOperation {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        $Definition,

        [Parameter(Mandatory)]
        [string] $Operation
    )

    if (-not $Definition.OperationSchemas) {
        return @{}
    }

    if ($Definition.OperationSchemas.Contains($Operation)) {
        return $Definition.OperationSchemas[$Operation]
    }

    return @{}
}

function Assert-ParsecCoreIngredientArgument {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        $Definition,

        [Parameter(Mandatory)]
        [string] $Operation,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Arguments
    )

    $schema = Get-ParsecCoreIngredientSchemaForOperation -Definition $Definition -Operation $Operation
    if (-not $schema -or $schema.Count -eq 0) {
        return
    }

    if ($schema.Contains('required')) {
        foreach ($required in @($schema.required)) {
            if ([string]::IsNullOrWhiteSpace([string] $required)) {
                continue
            }

            if (-not $Arguments.Contains($required)) {
                throw "Ingredient '$($Definition.Name)' operation '$Operation' requires argument '$required'."
            }
        }
    }

    if ($schema.Contains('types')) {
        foreach ($key in @($schema.types.Keys)) {
            if ($Arguments.Contains($key) -and -not (Test-ParsecCoreArgumentType -Value $Arguments[$key] -TypeName ([string] $schema.types[$key]))) {
                throw "Ingredient '$($Definition.Name)' operation '$Operation' argument '$key' must be of type '$($schema.types[$key])'."
            }
        }
    }
}
