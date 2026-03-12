Context 'display.set-activedisplays' {
    It 'captures and restores the active display topology' {
        Enable-ParsecIngredientDualMonitorEnvironment

        $capture = Invoke-ParsecIngredientOperation -Name 'display.set-activedisplays' -Operation 'capture' -Arguments @{
            screen_ids = @(1)
        } -RunState @{}

        $apply = Invoke-ParsecIngredientOperation -Name 'display.set-activedisplays' -Operation 'apply' -Arguments @{
            screen_ids = @(1)
        } -RunState @{}

        $reset = Invoke-ParsecIngredientOperation -Name 'display.set-activedisplays' -Operation 'reset' -Arguments @{} -ExecutionResult $capture -RunState @{}

        $capture.Status | Should -Be 'Succeeded'
        $apply.Status | Should -Be 'Succeeded'
        $apply.Outputs.target_state.monitors[1].enabled | Should -BeFalse
        $reset.Status | Should -Be 'Succeeded'
        (@($script:IngredientObservedState.monitors | Where-Object { $_.enabled })).Count | Should -Be 2
    }

    It 'fails when a requested screen id cannot be resolved' {
        $result = Invoke-ParsecIngredientOperation -Name 'display.set-activedisplays' -Operation 'apply' -Arguments @{
            screen_ids = @(99)
        } -RunState @{}

        $result.Status | Should -Be 'Failed'
        $result.Errors | Should -Contain 'MonitorNotFound'
    }
}
