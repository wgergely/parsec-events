$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

Describe 'Get-ParsecRecipe' {
    It 'loads the placeholder mission recipes' {
        $recipes = Get-ParsecRecipe

        $recipes.name | Should -Contain 'enter-mobile'
        $recipes.name | Should -Contain 'return-desktop'
    }

    It 'parses TOML arrays and step arguments from a fixture recipe' {
        $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\command-success.toml'
        $recipe = Get-ParsecRecipe -NameOrPath $recipePath

        $recipe.name | Should -Be 'command-success'
        $recipe.steps.Count | Should -Be 1
        $recipe.steps[0].arguments.arguments.Count | Should -Be 3
        $recipe.steps[0].arguments.arguments[1] | Should -Be '-Command'
    }
}
