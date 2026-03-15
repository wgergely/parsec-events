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
    Domain = 'display'
    Operations = @{
        capture = {
            param($ctx, $operationArguments, $prior)
            $captureArgs = [ordered]@{ domain = 'display ensured resolution' }
            foreach ($key in @($operationArguments.Keys)) { $captureArgs[$key] = $operationArguments[$key] }
            & $ctx.DomainApi.Invoke 'CaptureMonitorState' $captureArgs $prior $ctx.StateRoot $ctx.RunState
        }
        apply = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'ApplyEnsureResolution' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        verify = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'VerifyEnsureResolution' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        reset = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'ResetEnsureResolution' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
    }
}

