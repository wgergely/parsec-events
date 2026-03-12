function Get-ParsecDisplay {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    return @(Get-ParsecDisplayInventory -StateRoot $StateRoot)
}
