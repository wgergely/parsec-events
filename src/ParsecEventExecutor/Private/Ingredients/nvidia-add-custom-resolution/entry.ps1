param(
    [Parameter()]
    [System.Collections.IDictionary] $Schema,

    [Parameter()]
    [string] $IngredientPath
)

# Schema, IngredientPath required by ingredient entry contract
$null = $Schema
$null = $IngredientPath

return @{
    Domain = 'nvidia'
    Operations = @{
        apply = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'ApplyCustomResolution' $operationArguments $prior $ctx.StateRoot }
        wait = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'WaitCustomResolution' $operationArguments $prior $ctx.StateRoot }
        verify = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'VerifyCustomResolution' $operationArguments $prior $ctx.StateRoot }
    }
}

