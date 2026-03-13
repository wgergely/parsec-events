param(
    [Parameter()]
    [System.Collections.IDictionary] $Schema,

    [Parameter()]
    [string] $IngredientPath
)

return @{
    Domain = 'display'
    Operations = @{
        capture = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'CaptureScaling' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        apply = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'ApplyScaling' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        verify = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'VerifyScaling' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        reset = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'ResetScaling' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
    }
}

