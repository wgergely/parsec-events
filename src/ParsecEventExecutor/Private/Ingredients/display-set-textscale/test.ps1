Context 'display.set-textscale' {
    It 'captures text scaling state' {
        $capture = Invoke-ParsecCoreIngredientOperation -Name 'display.set-textscale' -Operation 'capture' -Arguments @{} -RunState @{}

        $capture.Status | Should -Be 'Succeeded'
        $capture.Outputs.captured_state.text_scale_percent | Should -Be 130
    }

    It 'resets text scaling from captured state' {
        $capture = Invoke-ParsecCoreIngredientOperation -Name 'display.set-textscale' -Operation 'capture' -Arguments @{} -RunState @{}
        $reset = Invoke-ParsecCoreIngredientOperation -Name 'display.set-textscale' -Operation 'reset' -Arguments @{} -Prior $capture -RunState @{}

        $reset.Status | Should -Be 'Succeeded'
        $reset.Outputs.text_scale_percent | Should -Be 130
    }
}
