Context 'service.stop' {
    It 'stops and verifies a service through the operation contract' {
        Mock Stop-Service {}
        Mock Get-Service {
            [pscustomobject]@{
                Name = 'Spooler'
                Status = 'Stopped'
            }
        } -ParameterFilter { $Name -eq 'Spooler' }

        $stop = Invoke-ParsecCoreIngredientOperation -Name 'service.stop' -Operation 'apply' -Arguments @{ service_name = 'Spooler' } -RunState @{}
        $verify = Invoke-ParsecCoreIngredientOperation -Name 'service.stop' -Operation 'verify' -Arguments @{ service_name = 'Spooler' } -Prior $stop -RunState @{}

        $stop.Status | Should -Be 'Succeeded'
        $verify.Status | Should -Be 'Succeeded'
        Should -Invoke Stop-Service -Times 1 -Exactly
    }
}
