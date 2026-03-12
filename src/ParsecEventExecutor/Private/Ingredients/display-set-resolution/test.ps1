Context 'display.set-resolution' {
    It 'captures resolution state for a mutating monitor ingredient' {
        $ingredient = Get-ParsecIngredient -Name 'display.set-resolution'
        $capture = Invoke-ParsecIngredientOperation -Name 'display.set-resolution' -Operation 'capture' -Arguments @{
            device_name = '\\.\DISPLAY1'
        } -RunState @{}

        $ingredient.Capabilities | Should -Contain 'capture'
        $capture.Status | Should -Be 'Succeeded'
        $capture.Outputs.captured_state.display.refresh_rate_hz | Should -Be 60
        $capture.Outputs.captured_state.display.scale_percent | Should -Be 150
        $capture.Outputs.captured_state.identity.scheme | Should -Be 'adapter_id+target_id'
        $capture.Outputs.captured_state.topology.is_active | Should -BeTrue
    }

    It 'resets resolution from captured state' {
        $capture = Invoke-ParsecIngredientOperation -Name 'display.set-resolution' -Operation 'capture' -Arguments @{
            device_name = '\\.\DISPLAY1'
        } -RunState @{}
        $reset = Invoke-ParsecIngredientOperation -Name 'display.set-resolution' -Operation 'reset' -Arguments @{} -ExecutionResult $capture -RunState @{}

        $reset.Status | Should -Be 'Succeeded'
        $reset.Requested.device_name | Should -Be '\\.\DISPLAY1'
        $reset.Requested.width | Should -Be 1920
        $reset.Requested.height | Should -Be 1080
    }
}
