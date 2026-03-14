Context 'command.invoke' {
    It 'captures structured command output' {
        $result = Invoke-ParsecCoreIngredientOperation -Name 'command.invoke' -Operation 'apply' -Arguments @{
            file_path = 'C:\Program Files\PowerShell\7\pwsh.exe'
            arguments = @('-NoProfile', '-Command', "Write-Output 'hello'")
        } -RunState @{}

        $result.Status | Should -Be 'Succeeded'
        $result.Outputs.stdout | Should -Be 'hello'
    }
}
