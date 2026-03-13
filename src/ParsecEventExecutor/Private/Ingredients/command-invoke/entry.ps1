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
            param($ctx, $args, $prior)
            & $ctx.DomainApi.Invoke 'RunProcess' $args
        }
    }
}
