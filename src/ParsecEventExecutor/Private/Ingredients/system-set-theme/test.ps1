Context 'system.set-theme' {
    It 'captures and restores theme through the theme ingredient' {
        $capture = Invoke-ParsecCoreIngredientOperation -Name 'system.set-theme' -Operation 'capture' -Arguments @{} -RunState @{}
        $apply = Invoke-ParsecCoreIngredientOperation -Name 'system.set-theme' -Operation 'apply' -Arguments @{ mode = 'Dark' } -RunState @{}
        $verify = Invoke-ParsecCoreIngredientOperation -Name 'system.set-theme' -Operation 'verify' -Arguments @{ mode = 'Dark' } -RunState @{}
        $reset = Invoke-ParsecCoreIngredientOperation -Name 'system.set-theme' -Operation 'reset' -Arguments @{ captured_state = $capture.Outputs.captured_state } -RunState @{}

        $capture.Status | Should -Be 'Succeeded'
        $capture.Outputs.captured_state.mode | Should -Be 'Dark'
        $apply.Status | Should -Be 'Succeeded'
        $verify.Status | Should -Be 'Succeeded'
        $reset.Status | Should -Be 'Succeeded'
    }
}
