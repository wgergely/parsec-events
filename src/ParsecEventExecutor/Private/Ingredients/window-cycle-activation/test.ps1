Context 'window.cycle-activation' {
    It 'captures the current foreground window and restores it after cycling' {
        $capture = Invoke-ParsecIngredientOperation -Name 'window.cycle-activation' -Operation 'capture' -Arguments @{} -RunState @{}
        $capture.Status | Should -Be 'Succeeded'
        $capture.Outputs.captured_state.foreground_window.handle | Should -Be 101

        $apply = Invoke-ParsecIngredientOperation -Name 'window.cycle-activation' -Operation 'apply' -Arguments @{ dwell_ms = 0 } -RunState @{}
        $apply.Status | Should -Be 'Succeeded'
        $apply.Outputs.restore_result.succeeded | Should -BeTrue
        $script:IngredientWindowForegroundHandle | Should -Be 101
        $script:IngredientWindowActivationLog | Should -Contain 102
    }

    It 'fails verification when the original foreground window is not restored' {
        $capture = Invoke-ParsecIngredientOperation -Name 'window.cycle-activation' -Operation 'capture' -Arguments @{} -RunState @{}
        $script:IngredientWindowForegroundHandle = 102

        $verify = Invoke-ParsecIngredientOperation -Name 'window.cycle-activation' -Operation 'verify' -Arguments @{} -ExecutionResult $capture -RunState @{}
        $verify.Status | Should -Be 'Failed'
        $verify.Errors | Should -Contain 'ForegroundWindowDrift'
    }
}
