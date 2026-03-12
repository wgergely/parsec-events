Context 'process.start' {
    It 'starts a process and resets it through the operation contract' {
        $start = Invoke-ParsecIngredientOperation -Name 'process.start' -Operation 'apply' -Arguments @{
            file_path = 'C:\Program Files\PowerShell\7\pwsh.exe'
            arguments = @('-NoProfile', '-Command', 'Start-Sleep -Seconds 10')
        } -RunState @{}

        $verifyStart = Invoke-ParsecIngredientOperation -Name 'process.start' -Operation 'verify' -Arguments @{
            file_path = 'C:\Program Files\PowerShell\7\pwsh.exe'
        } -ExecutionResult $start -RunState @{}

        $reset = Invoke-ParsecIngredientOperation -Name 'process.start' -Operation 'reset' -Arguments @{} -ExecutionResult $start -RunState @{}

        $verifyStart.Status | Should -Be 'Succeeded'
        $reset.Status | Should -Be 'Succeeded'
    }
}
