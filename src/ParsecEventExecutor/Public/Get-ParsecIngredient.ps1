function Get-ParsecIngredient {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $Name = '*'
    )

    $items = $script:ParsecIngredientRegistry.Values | Sort-Object Name
    if ($Name -ne '*') {
        if ($Name.IndexOfAny(@('*', '?')) -lt 0) {
            try {
                return Get-ParsecIngredientDefinition -Name $Name
            }
            catch {
                return @()
            }
        }

        $items = $items | Where-Object {
            $_.Name -like $Name -or @($_.Aliases) -like $Name
        }
    }

    return @($items)
}
