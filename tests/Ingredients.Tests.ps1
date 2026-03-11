$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

Describe 'Built-in ingredients' {
    InModuleScope ParsecEventExecutor {
        It 'invokes a command and captures structured output' {
            $result = Invoke-ParsecIngredientExecute -Name 'command.invoke' -Arguments @{
                file_path = 'C:\Program Files\PowerShell\7\pwsh.exe'
                arguments = @('-NoProfile', '-Command', "Write-Output 'hello'")
            } -RunState @{}

            $result.Status | Should -Be 'Succeeded'
            $result.Outputs.stdout | Should -Be 'hello'
        }

        It 'starts a process and compensates by stopping it' {
            $start = Invoke-ParsecIngredientExecute -Name 'process.start' -Arguments @{
                file_path = 'C:\Program Files\PowerShell\7\pwsh.exe'
                arguments = @('-NoProfile', '-Command', 'Start-Sleep -Seconds 10')
            } -RunState @{}

            $verifyStart = Invoke-ParsecIngredientVerify -Name 'process.start' -Arguments @{
                file_path = 'C:\Program Files\PowerShell\7\pwsh.exe'
            } -ExecutionResult $start -RunState @{}

            $compensation = Invoke-ParsecIngredientCompensate -Name 'process.start' -Arguments @{
                file_path = 'C:\Program Files\PowerShell\7\pwsh.exe'
            } -ExecutionResult $start -RunState @{}

            $stopVerify = Invoke-ParsecIngredientVerify -Name 'process.stop' -Arguments @{
                process_id = [int] $start.Outputs.process_id
            } -ExecutionResult (New-ParsecResult -Status 'Succeeded') -RunState @{}

            $verifyStart.Status | Should -Be 'Succeeded'
            $compensation.Status | Should -Be 'Succeeded'
            $stopVerify.Status | Should -Be 'Succeeded'
        }

        It 'validates service ingredient contracts through service command mocks' {
            Mock Start-Service {}
            Mock Stop-Service {}
            Mock Get-Service {
                [pscustomobject]@{
                    Name = 'Spooler'
                    Status = 'Running'
                }
            } -ParameterFilter { $Name -eq 'Spooler' }

            $start = Invoke-ParsecIngredientExecute -Name 'service.start' -Arguments @{ service_name = 'Spooler' } -RunState @{}
            $verify = Invoke-ParsecIngredientVerify -Name 'service.start' -Arguments @{ service_name = 'Spooler' } -ExecutionResult $start -RunState @{}

            $start.Status | Should -Be 'Succeeded'
            $verify.Status | Should -Be 'Succeeded'
            Should -Invoke Start-Service -Times 1 -Exactly
        }
    }
}
