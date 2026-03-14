Context 'display.set-orientation' {
    It 'captures orientation for a target monitor' {
        $capture = Invoke-ParsecCoreIngredientOperation -Name 'display.set-orientation' -Operation 'capture' -Arguments @{
            device_name = '\\.\DISPLAY1'
        } -RunState @{}

        $capture.Status | Should -Be 'Succeeded'
        $capture.Outputs.captured_state.orientation | Should -Be 'Landscape'
    }

    It 'resets orientation from captured state' {
        $capture = Invoke-ParsecCoreIngredientOperation -Name 'display.set-orientation' -Operation 'capture' -Arguments @{
            device_name = '\\.\DISPLAY1'
        } -RunState @{}
        $reset = Invoke-ParsecCoreIngredientOperation -Name 'display.set-orientation' -Operation 'reset' -Arguments @{} -Prior $capture -RunState @{}

        $reset.Status | Should -Be 'Succeeded'
        $reset.Requested.device_name | Should -Be '\\.\DISPLAY1'
        $reset.Requested.orientation | Should -Be 'Landscape'
    }
}
