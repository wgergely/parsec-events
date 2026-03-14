function Test-ParsecSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    return Invoke-ParsecCoreIngredientOperation -Name 'display.snapshot' -Operation 'verify' -Arguments @{ snapshot_name = $Name } -StateRoot $StateRoot -RunState @{}
}

function Test-ParsecProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    return Test-ParsecSnapshot -Name $Name -StateRoot $StateRoot
}
