function Start-ParsecExecutor {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [ValidateSet('VerifyOnly', 'Reconcile')]
        [string] $EventName = 'VerifyOnly',

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    if (-not $PSCmdlet.ShouldProcess($EventName, 'Start executor event')) {
        return
    }

    switch ($EventName) {
        'VerifyOnly' {
            return [pscustomobject]@{
                event_name = $EventName
                state = Get-ParsecExecutorStateDocument -StateRoot $StateRoot
                timestamp = [DateTimeOffset]::UtcNow.ToString('o')
            }
        }
        'Reconcile' {
            $state = Get-ParsecRecoveryStatus -StateRoot $StateRoot
            return [pscustomobject]@{
                event_name = $EventName
                last_applied_recipe = $state.last_applied_recipe
                last_event_type = $state.last_event_type
                active_snapshot = $state.active_snapshot
                issues = @($state.issues)
                recoverable = [bool] $state.recoverable
                recovery_candidate = $state.recovery_candidate
                status = $state.status
                timestamp = [DateTimeOffset]::UtcNow.ToString('o')
            }
        }
    }
}
