Context 'display.set-scaling' {
    It 'captures display and font scaling through the scaling ingredient' {
        $capture = Invoke-ParsecIngredientOperation -Name 'display.set-scaling' -Operation 'capture' -Arguments @{
            device_name = '\\.\DISPLAY1'
        } -RunState @{}

        $capture.Status | Should -Be 'Succeeded'
        $capture.Outputs.captured_state.scale_percent | Should -Be 150
        $capture.Outputs.captured_state.text_scale_percent | Should -Be 130
    }
}
