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
        capture = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'CaptureEnabled' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        apply = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'ApplyEnabled' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        verify = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'VerifyEnabled' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
        reset = { param($ctx, $operationArguments, $prior) & $ctx.DomainApi.Invoke 'ResetEnabled' $operationArguments $prior $ctx.StateRoot $ctx.RunState }
    }
}

