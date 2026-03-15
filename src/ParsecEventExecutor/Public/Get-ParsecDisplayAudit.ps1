function Get-ParsecDisplayAudit {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $domain = Get-ParsecCoreDomainDefinition -Name 'display'
    return & $domain.Api.Invoke 'GetAuditState' @{} $null $StateRoot @{}
}
