$supportFiles = @(
    (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Core\HostSupport.ps1')
)

$loadSupportFiles = {
    param($files)
    $module = $ExecutionContext.SessionState.Module
    if ($null -ne $module) {
        & $module {
            param($innerFiles)
            foreach ($file in @($innerFiles)) { . $file }
        } $files
        return
    }

    foreach ($file in @($files)) { . $file }
}.GetNewClosure()

return @{
    Name = 'command'
    Api = [pscustomobject]@{
        Invoke = {
            param(
                [string] $Method,
                [System.Collections.IDictionary] $Arguments = @{},
                $Prior,
                [string] $StateRoot = (Get-ParsecDefaultStateRoot),
                [System.Collections.IDictionary] $RunState = @{}
            )

            & $loadSupportFiles $supportFiles

            switch ($Method) {
                'Invoke' {
                    return & ([scriptblock]::Create([string] $Arguments.command))
                }
                'RunProcess' {
                    $stdout = New-Object System.Collections.Generic.List[string]
                    $stderr = New-Object System.Collections.Generic.List[string]
                    $exitCode = $null

                    try {
                        $output = & $Arguments.file_path @($Arguments.arguments) 2>&1
                        $exitCode = $LASTEXITCODE
                    }
                    catch {
                        $stderr.Add([string] $_)
                        return New-ParsecResult -Status 'Failed' -Message ("Failed to start command '{0}'." -f [string] $Arguments.file_path) -Requested $Arguments -Outputs @{
                            stdout = ''
                            stderr = ($stderr -join [Environment]::NewLine)
                            exit_code = -1
                        } -Errors @('ProcessLaunchFailed')
                    }

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
