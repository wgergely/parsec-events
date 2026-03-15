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

    It 'resets a stopped process by restarting it when it was originally running' {
        $start = Invoke-ParsecCoreIngredientOperation -Name 'process.start' -Operation 'apply' -Arguments @{
            file_path = 'C:\Program Files\PowerShell\7\pwsh.exe'
            arguments = @('-NoProfile', '-Command', 'Start-Sleep -Seconds 30')
        } -RunState @{}

        $originalPid = [int] $start.Outputs.process_id

        Invoke-ParsecCoreIngredientOperation -Name 'process.stop' -Operation 'apply' -Arguments @{
            process_id = $originalPid
        } -RunState @{} | Out-Null

        $reset = Invoke-ParsecCoreIngredientOperation -Name 'process.stop' -Operation 'reset' -Arguments @{
            file_path = 'C:\Program Files\PowerShell\7\pwsh.exe'
            arguments = @('-NoProfile', '-Command', 'Start-Sleep -Seconds 30')
            captured_state = @{
                is_running = $true
                file_path = 'C:\Program Files\PowerShell\7\pwsh.exe'
                argument_line = '-NoProfile -Command Start-Sleep -Seconds 30'
            }
        } -RunState @{}

        $reset.Status | Should -Be 'Succeeded'
        $reset.Outputs.process_id | Should -Not -BeNullOrEmpty

        # Clean up the restarted process
        Stop-Process -Id ([int] $reset.Outputs.process_id) -ErrorAction SilentlyContinue
    }

    It 'skips reset when the process was not running before stop' {
        $reset = Invoke-ParsecCoreIngredientOperation -Name 'process.stop' -Operation 'reset' -Arguments @{
            captured_state = @{
                is_running = $false
                file_path = 'C:\Program Files\PowerShell\7\pwsh.exe'
            }
        } -RunState @{}

        $reset.Status | Should -Be 'Succeeded'
    }
}
