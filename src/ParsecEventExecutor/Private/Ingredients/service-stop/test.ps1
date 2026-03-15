Context 'service.stop' {
    It 'stops and verifies a service through the operation contract' {
        $script:IngredientServiceStates['Spooler'] = 'Running'

        $stop = Invoke-ParsecCoreIngredientOperation -Name 'service.stop' -Operation 'apply' -Arguments @{ service_name = 'Spooler' } -RunState @{}
        $verify = Invoke-ParsecCoreIngredientOperation -Name 'service.stop' -Operation 'verify' -Arguments @{ service_name = 'Spooler' } -Prior $stop -RunState @{}

        $stop.Status | Should -Be 'Succeeded'
        $verify.Status | Should -Be 'Succeeded'
        $script:IngredientServiceStates['Spooler'] | Should -Be 'Stopped'
    }

    It 'resets a stopped service back to running when it was originally running' {
        $script:IngredientServiceStates['Spooler'] = 'Stopped'

        $reset = Invoke-ParsecCoreIngredientOperation -Name 'service.stop' -Operation 'reset' -Arguments @{
            service_name = 'Spooler'
            captured_state = @{
                service_name = 'Spooler'
                status = 'Running'
            }
        } -RunState @{}

        $reset.Status | Should -Be 'Succeeded'
        $script:IngredientServiceStates['Spooler'] | Should -Be 'Running'
    }

    It 'skips reset when the service was already stopped before apply' {
        $script:IngredientServiceStates['Spooler'] = 'Stopped'

        $reset = Invoke-ParsecCoreIngredientOperation -Name 'service.stop' -Operation 'reset' -Arguments @{
            service_name = 'Spooler'
            captured_state = @{
                service_name = 'Spooler'
                status = 'Stopped'
            }
        } -RunState @{}

        $reset.Status | Should -Be 'Succeeded'
        $script:IngredientServiceStates['Spooler'] | Should -Be 'Stopped'
    }
}
