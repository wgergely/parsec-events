function Get-ParsecIngredient {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $Name = '*'
    )

    $items = $script:ParsecIngredientRegistry.Values | Sort-Object Name
    if ($Name -ne '*') {
        $items = $items | Where-Object { $_.Name -like $Name }
    }

    return @($items)
}
