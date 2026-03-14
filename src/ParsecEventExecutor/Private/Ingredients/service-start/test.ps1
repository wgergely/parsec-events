Context 'service.start' {
    It 'validates service ingredient apply and verify operations' {
        Mock Start-Service {}
        Mock Stop-Service {}
        Mock Get-Service {
            [pscustomobject]@{
                Name = 'Spooler'
                Status = 'Running'
            }
        } -ParameterFilter { $Name -eq 'Spooler' }

        $start = Invoke-ParsecCoreIngredientOperation -Name 'service.start' -Operation 'apply' -Arguments @{ service_name = 'Spooler' } -RunState @{}
        $verify = Invoke-ParsecCoreIngredientOperation -Name 'service.start' -Operation 'verify' -Arguments @{ service_name = 'Spooler' } -Prior $start -RunState @{}

        $start.Status | Should -Be 'Succeeded'
        $verify.Status | Should -Be 'Succeeded'
        Should -Invoke Start-Service -Times 1 -Exactly
    }

    It 'captures service state through a mutating service ingredient' {
        Mock Get-Service {
            [pscustomobject]@{
                Name = 'Spooler'
                Status = 'Stopped'
            }
        } -ParameterFilter { $Name -eq 'Spooler' }

        $capture = Invoke-ParsecCoreIngredientOperation -Name 'service.start' -Operation 'capture' -Arguments @{
            service_name = 'Spooler'
        } -RunState @{}

        $capture.Status | Should -Be 'Succeeded'
        $capture.Outputs.captured_state.status | Should -Be 'Stopped'
    }
}
