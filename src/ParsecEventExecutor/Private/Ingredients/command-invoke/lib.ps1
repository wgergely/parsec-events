function Get-ParsecIngredientOperations {
    return @{
        apply = {
            param($Arguments, $ExecutionResult, $StateRoot, $RunState, $Definition)
            $output = & $Arguments.file_path @($Arguments.arguments) 2>&1
            $exitCode = $LASTEXITCODE
            $stdout = New-Object System.Collections.Generic.List[string]
            $stderr = New-Object System.Collections.Generic.List[string]
            foreach ($record in @($output)) {
                if ($record -is [System.Management.Automation.ErrorRecord]) {
                    $stderr.Add([string] $record)
                }
                else {
                    $stdout.Add([string] $record)
                }
            }
            if ($null -eq $exitCode -or $exitCode -eq 0) {
                $status = 'Succeeded'
                $message = 'Command completed successfully.'
                $normalizedExitCode = 0
            }
            else {
                $status = 'Failed'
                $message = "Command exited with code $exitCode."
                $normalizedExitCode = [int] $exitCode
            }
            $result = New-ParsecResult -Status $status -Message $message -Requested $Arguments -Outputs @{ stdout = ($stdout -join [Environment]::NewLine); stderr = ($stderr -join [Environment]::NewLine); exit_code = $normalizedExitCode }
            if ($normalizedExitCode -ne 0) {
                $result.Errors = @('NonZeroExitCode')
            }
            return $result
        }
    }
}
