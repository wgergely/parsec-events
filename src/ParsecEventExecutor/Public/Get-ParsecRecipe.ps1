function Get-ParsecRecipe {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'Path')]
        [string] $NameOrPath = '*'
    )

    process {
        if ($NameOrPath -eq '*') {
            $recipeRoot = Join-Path -Path (Get-ParsecRepositoryRoot) -ChildPath 'recipes'
            foreach ($file in Get-ChildItem -LiteralPath $recipeRoot -Filter '*.toml' -File | Sort-Object Name) {
                Get-ParsecRecipeDocument -NameOrPath $file.FullName
            }

            return
        }

        Get-ParsecRecipeDocument -NameOrPath $NameOrPath
    }
}
