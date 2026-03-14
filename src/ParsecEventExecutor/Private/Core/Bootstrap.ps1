function Get-ParsecCoreLoadOrder {
    [CmdletBinding()]
    [OutputType([string[]])]
    [OutputType([System.Object[]])]
    param()

    return @(
        'Definitions.ps1',
        'Registry.ps1',
        'Schema.ps1',
        'Context.ps1',
        'PackageScope.ps1',
        'StateHelpers.ps1',
        'Dispatcher.ps1',
        'Loader.ps1'
    )
}
