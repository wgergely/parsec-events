return @{
    Name = 'command'
    Api = [pscustomobject]@{
        Invoke = {
            param(
                [string] $Method,
                [System.Collections.IDictionary] $Arguments = @{}
            )

            switch ($Method) {
                'Invoke' {
                    return & ([scriptblock]::Create([string] $Arguments.command))
                }
                'RunProcess' {
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
                        $errors = @()
                    }
                    else {
                        $status = 'Failed'
                        $message = "Command exited with code $exitCode."
                        $normalizedExitCode = [int] $exitCode
                        $errors = @('NonZeroExitCode')
                    }

                    return New-ParsecResult -Status $status -Message $message -Requested $Arguments -Outputs @{
                        stdout = ($stdout -join [Environment]::NewLine)
                        stderr = ($stderr -join [Environment]::NewLine)
                        exit_code = $normalizedExitCode
                    } -Errors $errors
                }
                default { throw "Command domain method '$Method' is not available." }
            }
        }
    }
}
