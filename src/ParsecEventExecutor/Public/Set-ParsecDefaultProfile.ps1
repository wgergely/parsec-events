function Set-ParsecDefaultProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    if (-not $PSCmdlet.ShouldProcess('default', 'Capture current system state as default profile')) {
        return
    }

    $snapshot = Save-ParsecSnapshot -Name 'default' -StateRoot $StateRoot -Confirm:$false

    $executorState = Get-ParsecExecutorStateDocument -StateRoot $StateRoot
    $executorState.default_profile = 'default'
    Save-ParsecExecutorStateDocument -StateDocument $executorState -StateRoot $StateRoot | Out-Null

    return $snapshot
}
