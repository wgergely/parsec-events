param(
    [Parameter()]
    [System.Collections.IDictionary] $Schema,

    [Parameter()]
    [string] $IngredientPath
)

return @{
    Domain = 'service'
    Operations = @{
        capture = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'Capture' $operationArguments $prior }
        apply = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'Stop' $operationArguments $prior }
        verify = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'VerifyStopped' $operationArguments $prior }
    }
}

