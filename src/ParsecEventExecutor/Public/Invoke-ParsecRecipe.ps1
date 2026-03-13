function Invoke-ParsecRecipe {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Name', 'Path')]
        [string] $NameOrPath,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $recipe = Get-ParsecRecipeDocument -NameOrPath $NameOrPath
    if (-not $PSCmdlet.ShouldProcess($recipe.name, 'Invoke recipe')) {
        return
    }

    return Invoke-ParsecRecipeInternal -Recipe $recipe -StateRoot $StateRoot
}
