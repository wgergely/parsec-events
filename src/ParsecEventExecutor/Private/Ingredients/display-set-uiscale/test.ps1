Context 'display.set-uiscale' {
    It 'captures UI scaling state' {
        $capture = Invoke-ParsecIngredientOperation -Name 'display.set-uiscale' -Operation 'capture' -Arguments @{} -RunState @{}

        $capture.Status | Should -Be 'Succeeded'
        $capture.Outputs.captured_state.ui_scale_percent | Should -Be 150
    }

    It 'resets UI scaling from captured state' {
        $capture = Invoke-ParsecIngredientOperation -Name 'display.set-uiscale' -Operation 'capture' -Arguments @{} -RunState @{}
        $reset = Invoke-ParsecIngredientOperation -Name 'display.set-uiscale' -Operation 'reset' -Arguments @{} -ExecutionResult $capture -RunState @{}

        $reset.Status | Should -Be 'Succeeded'
        $reset.Outputs.ui_scale_percent | Should -Be 150
    }
}
