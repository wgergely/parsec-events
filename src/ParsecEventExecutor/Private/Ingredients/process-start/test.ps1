Context 'process.start' {
    It 'starts a process and resets it through the operation contract' {
        $start = Invoke-ParsecCoreIngredientOperation -Name 'process.start' -Operation 'apply' -Arguments @{
            file_path = 'C:\Program Files\PowerShell\7\pwsh.exe'
            arguments = @('-NoProfile', '-Command', 'Start-Sleep -Seconds 10')
        } -RunState @{}

        $verifyStart = Invoke-ParsecCoreIngredientOperation -Name 'process.start' -Operation 'verify' -Arguments @{
            file_path = 'C:\Program Files\PowerShell\7\pwsh.exe'
        } -Prior $start -RunState @{}

        $reset = Invoke-ParsecCoreIngredientOperation -Name 'process.start' -Operation 'reset' -Arguments @{} -Prior $start -RunState @{}

        $verifyStart.Status | Should -Be 'Succeeded'
        $reset.Status | Should -Be 'Succeeded'
    }
}
