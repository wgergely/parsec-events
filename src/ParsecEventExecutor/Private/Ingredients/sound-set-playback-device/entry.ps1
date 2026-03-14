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
    Domain = 'sound'
    Operations = @{
        capture = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'Capture' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        apply = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'SetPlaybackDevice' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        verify = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'VerifyPlaybackDevice' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        reset = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'ResetPlaybackDevice' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
    }
}
