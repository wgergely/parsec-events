param(
    [Parameter()]
    [System.Collections.IDictionary] $Schema,

    [Parameter()]
    [string] $IngredientPath
)

return @{
    Domain = 'display'
    Operations = @{
        capture = {
            param($ctx, $operationArguments, $prior)
            $captureArgs = [ordered]@{ domain = 'display resolution' }
            foreach ($key in @($operationArguments.Keys)) { $captureArgs[$key] = $operationArguments[$key] }
            & $ctx.DomainApi.Invoke 'CaptureMonitorState' $captureArgs $prior $ctx.StateRoot $ctx.RunState
        }
        apply = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'ApplyResolution' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        wait = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'WaitResolution' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        verify = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'VerifyResolution' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        reset = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'ResetResolution' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
    }
}

