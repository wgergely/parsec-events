Context 'display.set-uiscale' {
    It 'captures UI scaling state' {
        $capture = Invoke-ParsecCoreIngredientOperation -Name 'display.set-uiscale' -Operation 'capture' -Arguments @{} -RunState @{}

        $capture.Status | Should -Be 'Succeeded'
        $capture.Outputs.captured_state.ui_scale_percent | Should -Be 150
    }

    It 'resets UI scaling from captured state' {
        $capture = Invoke-ParsecCoreIngredientOperation -Name 'display.set-uiscale' -Operation 'capture' -Arguments @{} -RunState @{}
        $reset = Invoke-ParsecCoreIngredientOperation -Name 'display.set-uiscale' -Operation 'reset' -Arguments @{} -Prior $capture -RunState @{}

        $reset.Status | Should -Be 'Succeeded'
        $reset.Outputs.ui_scale_percent | Should -Be 150
    }

    It 'preserves the adapter applied UI scale for readiness and verify' {
        $script:IngredientUiScaleMinimum = 100
        $script:IngredientUiScaleMaximum = 125

        $apply = Invoke-ParsecCoreIngredientOperation -Name 'display.set-uiscale' -Operation 'apply' -Arguments @{
            ui_scale_percent = 80
        } -RunState @{}
        $wait = Invoke-ParsecCoreIngredientOperation -Name 'display.set-uiscale' -Operation 'wait' -Arguments @{
            ui_scale_percent = 80
        } -Prior $apply -RunState @{}
        $verify = Invoke-ParsecCoreIngredientOperation -Name 'display.set-uiscale' -Operation 'verify' -Arguments @{
            ui_scale_percent = 80
        } -Prior $apply -RunState @{}

        $apply.Status | Should -Be 'Succeeded'
        $apply.Outputs.ui_scale_percent | Should -Be 100
        $wait.Status | Should -Be 'Succeeded'
        $wait.Outputs.ui_scale_percent | Should -Be 100
        $verify.Status | Should -Be 'Succeeded'
        $verify.Outputs.ui_scale_percent | Should -Be 100
    }
}
