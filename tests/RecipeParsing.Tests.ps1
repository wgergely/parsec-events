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
        $recipe.steps[0].operation | Should -Be 'apply'
        $recipe.steps[0].arguments.arguments.Count | Should -Be 3
        $recipe.steps[0].arguments.arguments[1] | Should -Be '-Command'
    }

    It 'resolves ingredient definitions with step argument overrides' {
        $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\definition-overrides.toml'
        $recipe = Get-ParsecRecipe -NameOrPath $recipePath

        $recipe.ingredient_definitions.Contains('base-command') | Should -BeTrue
        $recipe.steps[0].definition | Should -Be 'base-command'
        $recipe.steps[0].ingredient | Should -Be 'command.invoke'
        $recipe.steps[0].retry_count | Should -Be 2
        $recipe.steps[0].arguments.arguments[2] | Should -Be "Write-Output 'override'"
    }

    It 'parses the mission recipes as mobile preset and snapshot reset flows' {
        $mobile = Get-ParsecRecipe -NameOrPath 'enter-mobile'
        $desktop = Get-ParsecRecipe -NameOrPath 'return-desktop'

        $mobile.steps[0].ingredient | Should -Be 'display.snapshot'
        $mobile.steps[0].operation | Should -Be 'capture'
        $mobile.steps[1].ingredient | Should -Be 'display.ensure-resolution'
        $mobile.steps[1].arguments.width | Should -Be 2000
        $mobile.steps[1].arguments.height | Should -Be 3000
        $mobile.steps[2].arguments.ui_scale_percent | Should -Be 300
        $mobile.steps[3].arguments.text_scale_percent | Should -Be 125
        $mobile.steps[4].arguments.mode | Should -Be 'Light'
        $desktop.steps[0].ingredient | Should -Be 'display.snapshot'
        $desktop.steps[0].operation | Should -Be 'reset'
    }
}
