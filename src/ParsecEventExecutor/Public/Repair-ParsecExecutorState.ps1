function Repair-ParsecExecutorState {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    if (-not $PSCmdlet.ShouldProcess($StateRoot, 'Repair executor state from journal')) {
        return
    }

    return Repair-ParsecExecutorStateDocumentInternal -StateRoot $StateRoot
}
