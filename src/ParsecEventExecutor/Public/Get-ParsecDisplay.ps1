function Get-ParsecDisplay {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    [OutputType([System.Object[]])]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $domain = Get-ParsecCoreDomainDefinition -Name 'display'
    return @(& $domain.Api.Invoke 'GetInventory' @{} $null $StateRoot @{})
}
