Context 'service.stop' {
    It 'stops and verifies a service through the operation contract' {
        $script:IngredientServiceStates['Spooler'] = 'Running'

        $stop = Invoke-ParsecCoreIngredientOperation -Name 'service.stop' -Operation 'apply' -Arguments @{ service_name = 'Spooler' } -RunState @{}
        $verify = Invoke-ParsecCoreIngredientOperation -Name 'service.stop' -Operation 'verify' -Arguments @{ service_name = 'Spooler' } -Prior $stop -RunState @{}

        $stop.Status | Should -Be 'Succeeded'
        $verify.Status | Should -Be 'Succeeded'
        $script:IngredientServiceStates['Spooler'] | Should -Be 'Stopped'
    }
}
