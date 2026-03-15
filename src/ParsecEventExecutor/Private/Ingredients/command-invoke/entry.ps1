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
    Domain = 'command'
    Operations = @{
        apply = {
            param($ctx, $operationArguments, $prior)
            & $ctx.DomainApi.Invoke 'RunProcess' $operationArguments $prior $ctx.StateRoot $ctx.RunState
        }
    }
}
