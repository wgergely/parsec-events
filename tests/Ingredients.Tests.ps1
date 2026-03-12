$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

Describe 'Built-in ingredients' {
    InModuleScope ParsecEventExecutor {
        BeforeEach {
            . (Join-Path $PSScriptRoot 'IngredientTestSupport.ps1')
            Initialize-ParsecIngredientTestEnvironment
        }

        $ingredientTestRoot = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\Private\Ingredients'
        $ingredientTestFiles = Get-ChildItem -Path $ingredientTestRoot -Filter 'test.ps1' -Recurse -File | Sort-Object FullName
        foreach ($ingredientTestFile in $ingredientTestFiles) {
            . $ingredientTestFile.FullName
        }
    }
}
