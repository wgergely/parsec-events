function Get-ParsecDisplay {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $domain = Get-ParsecCoreDomainDefinition -Name 'display'
    return @(& $domain.Api.Invoke 'GetInventory' @{} $null $StateRoot @{})
}
