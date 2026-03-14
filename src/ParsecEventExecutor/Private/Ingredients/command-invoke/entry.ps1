param(
    [Parameter()]
    [System.Collections.IDictionary] $Schema,

    [Parameter()]
    [string] $IngredientPath
)

return @{
    Domain = 'command'
    Operations = @{
        apply = {
            param($ctx, $operationArguments, $prior)
            & $ctx.DomainApi.Invoke 'RunProcess' $operationArguments $prior $ctx.StateRoot $ctx.RunState
        }
    }
}
