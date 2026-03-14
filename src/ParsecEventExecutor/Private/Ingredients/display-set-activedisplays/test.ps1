Context 'display.set-activedisplays' {
    It 'captures and restores the active display topology' {
        $stateRoot = Join-Path $TestDrive 'active-displays-ingredient'
        Enable-ParsecIngredientDualMonitorEnvironment

        $capture = Invoke-ParsecCoreIngredientOperation -Name 'display.set-activedisplays' -Operation 'capture' -Arguments @{
            screen_ids = @(1)
        } -StateRoot $stateRoot -RunState @{}

        $apply = Invoke-ParsecCoreIngredientOperation -Name 'display.set-activedisplays' -Operation 'apply' -Arguments @{
            screen_ids = @(1)
        } -StateRoot $stateRoot -RunState @{}

        $reset = Invoke-ParsecCoreIngredientOperation -Name 'display.set-activedisplays' -Operation 'reset' -Arguments @{} -Prior $capture -StateRoot $stateRoot -RunState @{}

        $capture.Status | Should -Be 'Succeeded'
        $apply.Status | Should -Be 'Succeeded'
        @($apply.Outputs.target_state.monitors | Where-Object { $_.enabled }).Count | Should -Be 1
        @($apply.Outputs.requested_screen_ids).Count | Should -Be 1
        $reset.Status | Should -Be 'Succeeded'
        (@($script:IngredientObservedState.monitors | Where-Object { $_.enabled })).Count | Should -Be 2
    }

    It 'fails when a requested screen id cannot be resolved' {
        $stateRoot = Join-Path $TestDrive 'active-displays-ingredient-invalid'
        $result = Invoke-ParsecCoreIngredientOperation -Name 'display.set-activedisplays' -Operation 'apply' -Arguments @{
            screen_ids = @(99)
        } -StateRoot $stateRoot -RunState @{}

        $result.Status | Should -Be 'Failed'
        $result.Errors | Should -Contain 'MonitorNotFound'
    }
}
