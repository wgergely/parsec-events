function Get-ParsecCoreLoadOrder {
    [CmdletBinding()]
    param()

    return @(
        'Definitions.ps1',
        'Registry.ps1',
        'Schema.ps1',
        'Context.ps1',
        'Dispatcher.ps1',
        'Loader.ps1'
    )
}
