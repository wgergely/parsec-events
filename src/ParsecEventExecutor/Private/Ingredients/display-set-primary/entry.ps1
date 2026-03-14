param(
    [Parameter()]
    [System.Collections.IDictionary] $Schema,

    [Parameter()]
    [string] $IngredientPath
)

return @{
    Domain = 'display'
    Operations = @{
        capture = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'CapturePrimary' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        apply = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'ApplyPrimary' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        verify = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'VerifyPrimary' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        reset = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'ResetPrimary' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
    }
}

