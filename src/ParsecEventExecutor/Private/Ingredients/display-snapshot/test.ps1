Context 'display.snapshot' {
    It 'exposes manifest capabilities for display snapshots' {
        $ingredient = Get-ParsecIngredient -Name 'display.snapshot'

        $ingredient.Capabilities | Should -Contain 'capture'
        $ingredient.Capabilities | Should -Contain 'reset'
        $ingredient.Capabilities | Should -Contain 'verify'
        $ingredient.Kind | Should -Be 'display'
    }
}
