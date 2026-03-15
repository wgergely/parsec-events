Context 'service.start' {
    It 'validates service ingredient apply and verify operations' {
        $start = Invoke-ParsecCoreIngredientOperation -Name 'service.start' -Operation 'apply' -Arguments @{ service_name = 'Spooler' } -RunState @{}
        $verify = Invoke-ParsecCoreIngredientOperation -Name 'service.start' -Operation 'verify' -Arguments @{ service_name = 'Spooler' } -Prior $start -RunState @{}

        $start.Status | Should -Be 'Succeeded'
        $verify.Status | Should -Be 'Succeeded'
        $script:IngredientServiceStates['Spooler'] | Should -Be 'Running'
    }

    It 'captures service state through a mutating service ingredient' {
        $script:IngredientServiceStates['Spooler'] = 'Stopped'

        $capture = Invoke-ParsecCoreIngredientOperation -Name 'service.start' -Operation 'capture' -Arguments @{
            service_name = 'Spooler'
        } -RunState @{}

        $capture.Status | Should -Be 'Succeeded'
        $capture.Outputs.captured_state.status | Should -Be 'Stopped'
    }
}
