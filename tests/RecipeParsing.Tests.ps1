$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

Describe 'Get-ParsecRecipe' {
    It 'loads the dev fixture recipes' {
        $connectPath = Join-Path $PSScriptRoot 'fixtures\recipes\dev-connect.toml'
        $disconnectPath = Join-Path $PSScriptRoot 'fixtures\recipes\dev-disconnect.toml'
        $recipes = @(
            (Get-ParsecRecipe -NameOrPath $connectPath),
            (Get-ParsecRecipe -NameOrPath $disconnectPath)
        )

        $recipes.name | Should -Contain 'dev-connect'
        $recipes.name | Should -Contain 'dev-disconnect'
    }

    It 'parses TOML arrays and step arguments from a fixture recipe' {
        $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\command-success.toml'
        $recipe = Get-ParsecRecipe -NameOrPath $recipePath

        $recipe.name | Should -Be 'command-success'
        $recipe.event_type | Should -BeNullOrEmpty
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

    It 'parses a direct no-mode recipe that uses a flat ingredient alias' {
        $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\resolution-sequence.toml'
        $recipe = Get-ParsecRecipe -NameOrPath $recipePath

        $recipe.event_type | Should -BeNullOrEmpty
        $recipe.steps.Count | Should -Be 1
        $recipe.steps[0].ingredient | Should -Be 'set-resolution'
        $recipe.steps[0].arguments.width | Should -Be 1280
        $recipe.steps[0].arguments.height | Should -Be 720
    }

    It 'parses an array argument for the active-display ingredient' {
        $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\active-display-sequence.toml'
        $recipe = Get-ParsecRecipe -NameOrPath $recipePath

        $recipe.steps.Count | Should -Be 1
        $recipe.steps[0].ingredient | Should -Be 'set-activedisplays'
        @($recipe.steps[0].arguments.screen_ids).Count | Should -Be 1
        $recipe.steps[0].arguments.screen_ids[0] | Should -Be 1
    }

    It 'parses a direct orientation recipe that uses the flat alias' {
        $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\orientation-sequence.toml'
        $recipe = Get-ParsecRecipe -NameOrPath $recipePath

        $recipe.steps.Count | Should -Be 1
        $recipe.steps[0].ingredient | Should -Be 'set-orientation'
        $recipe.steps[0].arguments.orientation | Should -Be 'Portrait'
    }

    It 'parses a direct text-scale recipe that uses the flat alias' {
        $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\textscale-sequence.toml'
        $recipe = Get-ParsecRecipe -NameOrPath $recipePath

        $recipe.steps.Count | Should -Be 1
        $recipe.steps[0].ingredient | Should -Be 'set-textscale'
        $recipe.steps[0].arguments.text_scale_percent | Should -Be 150
    }

    It 'parses a direct ui-scale recipe that uses the flat alias' {
        $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\uiscale-sequence.toml'
        $recipe = Get-ParsecRecipe -NameOrPath $recipePath

        $recipe.steps.Count | Should -Be 1
        $recipe.steps[0].ingredient | Should -Be 'set-uiscale'
        $recipe.steps[0].arguments.ui_scale_percent | Should -Be 125
    }

    It 'parses the dev fixture recipes as connect preset and snapshot reset flows' {
        $connectPath = Join-Path $PSScriptRoot 'fixtures\recipes\dev-connect.toml'
        $disconnectPath = Join-Path $PSScriptRoot 'fixtures\recipes\dev-disconnect.toml'
        $connect = Get-ParsecRecipe -NameOrPath $connectPath
        $disconnect = Get-ParsecRecipe -NameOrPath $disconnectPath

        $connect.steps[0].ingredient | Should -Be 'display.snapshot'
        $connect.steps[0].operation | Should -Be 'capture'
        $connect.steps[1].ingredient | Should -Be 'display.ensure-resolution'
        $connect.steps[1].arguments.width | Should -Be 2000
        $connect.steps[1].arguments.height | Should -Be 3000
        $connect.steps[2].arguments.ui_scale_percent | Should -Be 300
        $connect.steps[3].arguments.text_scale_percent | Should -Be 125
        $connect.steps[4].arguments.mode | Should -Be 'Light'
        $disconnect.steps[0].ingredient | Should -Be 'display.snapshot'
        $disconnect.steps[0].operation | Should -Be 'reset'
    }
}
