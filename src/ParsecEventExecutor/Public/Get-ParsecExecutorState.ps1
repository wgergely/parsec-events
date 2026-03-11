function Get-ParsecExecutorState {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    return Get-ParsecExecutorStateDocument -StateRoot $StateRoot
}
