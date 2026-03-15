function Get-ParsecIngredient {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    [OutputType([System.Object[]])]
    param(
        [Parameter()]
        [string] $Name = '*'
    )

    if ($Name -ne '*') {
        if ($Name.IndexOfAny(@('*', '?')) -lt 0) {
            try {
                return Get-ParsecCoreIngredientDefinition -Name $Name
            }
            catch {
                return @()
            }
        }

        $items = if (Get-Command -Name Get-ParsecCoreIngredientDefinitions -ErrorAction SilentlyContinue) {
            Get-ParsecCoreIngredientDefinitions
        }
        else {
            $script:ParsecIngredientRegistry.Values | Sort-Object Name
        }

        $items = $items | Where-Object {
            $_.Name -like $Name -or @($_.Aliases) -like $Name
        }

        return @($items)
    }

    $items = if (Get-Command -Name Get-ParsecCoreIngredientDefinitions -ErrorAction SilentlyContinue) {
        Get-ParsecCoreIngredientDefinitions
    }
    else {
        $script:ParsecIngredientRegistry.Values | Sort-Object Name
    }

    return @($items)
}
