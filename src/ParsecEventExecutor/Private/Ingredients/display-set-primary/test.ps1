Context 'display.set-primary' {
    It 'captures primary-display state for a target monitor' {
        $capture = Invoke-ParsecCoreIngredientOperation -Name 'display.set-primary' -Operation 'capture' -Arguments @{
            device_name = '\\.\DISPLAY1'
        } -RunState @{}

        $capture.Status | Should -Be 'Succeeded'
        $capture.Outputs.captured_state.primary_monitor.is_primary | Should -BeTrue
        $capture.Outputs.captured_state.requested_monitor.device_name | Should -Be '\\.\DISPLAY1'
    }

    It 'resets primary-display state from captured state' {
        $capture = Invoke-ParsecCoreIngredientOperation -Name 'display.set-primary' -Operation 'capture' -Arguments @{
            device_name = '\\.\DISPLAY1'
        } -RunState @{}
        $reset = Invoke-ParsecCoreIngredientOperation -Name 'display.set-primary' -Operation 'reset' -Arguments @{} -Prior $capture -RunState @{}

        $reset.Status | Should -Be 'Succeeded'
        $reset.Requested.device_name | Should -Be '\\.\DISPLAY1'
    }
}
