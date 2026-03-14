Context 'process.stop' {
    It 'verifies that a stopped process is no longer running' {
        $start = Invoke-ParsecCoreIngredientOperation -Name 'process.start' -Operation 'apply' -Arguments @{
            file_path = 'C:\Program Files\PowerShell\7\pwsh.exe'
            arguments = @('-NoProfile', '-Command', 'Start-Sleep -Seconds 10')
        } -RunState @{}

        Invoke-ParsecCoreIngredientOperation -Name 'process.stop' -Operation 'apply' -Arguments @{
            process_id = [int] $start.Outputs.process_id
        } -RunState @{} | Out-Null

        $verify = Invoke-ParsecCoreIngredientOperation -Name 'process.stop' -Operation 'verify' -Arguments @{
            process_id = [int] $start.Outputs.process_id
        } -Prior (New-ParsecResult -Status 'Succeeded') -RunState @{}

        $verify.Status | Should -Be 'Succeeded'
    }
}
