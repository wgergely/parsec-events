param(
    [Parameter()]
    [System.Collections.IDictionary] $Schema,

    [Parameter()]
    [string] $IngredientPath
)

return @{
    Domain = 'display'
    Operations = @{
        capture = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'CaptureActiveDisplays' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        apply = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'ApplyActiveDisplays' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        wait = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'WaitActiveDisplays' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        verify = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'VerifyActiveDisplays' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        reset = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'ResetActiveDisplays' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
    }
}

