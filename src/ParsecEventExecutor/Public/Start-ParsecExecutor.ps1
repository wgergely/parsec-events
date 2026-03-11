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
        'SwitchToMobile' { return Invoke-ParsecRecipe -NameOrPath 'enter-mobile' -StateRoot $StateRoot }
        'SwitchToDesktop' { return Invoke-ParsecRecipe -NameOrPath 'return-desktop' -StateRoot $StateRoot }
        'VerifyOnly' {
            return [pscustomobject]@{
                event_name = $EventName
                state      = Get-ParsecExecutorStateDocument -StateRoot $StateRoot
                timestamp  = [DateTimeOffset]::UtcNow.ToString('o')
            }
        }
        'Reconcile' {
            $state = Get-ParsecExecutorStateDocument -StateRoot $StateRoot
            return [pscustomobject]@{
                event_name     = $EventName
                desired_mode   = $state.desired_mode
                actual_mode    = $state.actual_mode
                last_good_mode = $state.last_good_mode
                status         = if ($state.desired_mode -and $state.desired_mode -ne $state.actual_mode) { 'NeedsIntervention' } else { 'Converged' }
                timestamp      = [DateTimeOffset]::UtcNow.ToString('o')
            }
        }
    }
}
