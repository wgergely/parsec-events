Context 'display.set-enabled' {
    It 'captures enabled state for a target monitor' {
        $capture = Invoke-ParsecCoreIngredientOperation -Name 'display.set-enabled' -Operation 'capture' -Arguments @{
            device_name = '\\.\DISPLAY1'
        } -RunState @{}

        $capture.Status | Should -Be 'Succeeded'
        $capture.Outputs.captured_state.enabled | Should -BeTrue
        $capture.Outputs.captured_state.identity.scheme | Should -Be 'adapter_id+target_id'
    }

    It 'resets enabled state from captured state' {
        $capture = Invoke-ParsecCoreIngredientOperation -Name 'display.set-enabled' -Operation 'capture' -Arguments @{
            device_name = '\\.\DISPLAY1'
        } -RunState @{}
        $reset = Invoke-ParsecCoreIngredientOperation -Name 'display.set-enabled' -Operation 'reset' -Arguments @{} -Prior $capture -RunState @{}

        $reset.Status | Should -Be 'Succeeded'
        $reset.Requested.device_name | Should -Be '\\.\DISPLAY1'
        $reset.Requested.enabled | Should -BeTrue
    }
}
