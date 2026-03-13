param(
    [Parameter()]
    [System.Collections.IDictionary] $Schema,

    [Parameter()]
    [string] $IngredientPath
)

return @{
    Domain = 'display'
    Operations = @{
        capture = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'CaptureSnapshot' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        verify = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'VerifySnapshot' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        reset = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'ResetSnapshot' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
    }
}

