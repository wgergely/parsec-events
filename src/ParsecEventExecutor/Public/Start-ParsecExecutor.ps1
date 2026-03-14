function Start-ParsecExecutor {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [ValidateSet('SwitchToMobile', 'SwitchToDesktop', 'VerifyOnly', 'Reconcile')]
        [string] $EventName = 'VerifyOnly',

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    if (-not $PSCmdlet.ShouldProcess($EventName, 'Start executor event')) {
        return
    }

    switch ($EventName) {
        'SwitchToMobile' {
            $recipe = Get-ParsecRecipeDocument -NameOrPath 'enter-mobile'
            return Invoke-ParsecRecipeInternal -Recipe $recipe -StateRoot $StateRoot
        }
        'SwitchToDesktop' {
            $recipe = Get-ParsecRecipeDocument -NameOrPath 'return-desktop'
            return Invoke-ParsecRecipeInternal -Recipe $recipe -StateRoot $StateRoot
        }
        'VerifyOnly' {
            return [pscustomobject]@{
                event_name = $EventName
                state      = Get-ParsecExecutorStateDocument -StateRoot $StateRoot
                timestamp  = [DateTimeOffset]::UtcNow.ToString('o')
            }
        }
        'Reconcile' {
            $state = Get-ParsecRecoveryStatus -StateRoot $StateRoot
            return [pscustomobject]@{
                event_name      = $EventName
                desired_mode    = $state.desired_mode
                actual_mode     = $state.actual_mode
                last_good_mode  = $state.last_good_mode
                active_snapshot = $state.active_snapshot
                issues          = @($state.issues)
                recoverable     = [bool] $state.recoverable
                recovery_candidate = $state.recovery_candidate
                status          = $state.status
                timestamp       = [DateTimeOffset]::UtcNow.ToString('o')
            }
        }
    }
}
