$supportFiles = @(
    (Join-Path -Path (Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent) -ChildPath 'Core\HostSupport.ps1')
)

$resolveProcess = {
    param(
        [System.Collections.IDictionary] $Arguments = @{},
        $ExecutionResult
    )

    $processId = $null
    $executionOutputs = $null
    if ($ExecutionResult -is [System.Collections.IDictionary]) {
        if ($ExecutionResult.Contains('Outputs')) {
            $executionOutputs = $ExecutionResult['Outputs']
        }
    }
    elseif ($null -ne $ExecutionResult -and $ExecutionResult.PSObject.Properties.Name -contains 'Outputs') {
        $executionOutputs = $ExecutionResult.Outputs
    }

    if ($executionOutputs -is [System.Collections.IDictionary]) {
        if ($executionOutputs.Contains('process_id') -and $null -ne $executionOutputs.process_id) {
            $processId = [int] $executionOutputs.process_id
        }
    }
    elseif ($null -ne $executionOutputs -and $executionOutputs.PSObject.Properties.Name -contains 'process_id' -and $null -ne $executionOutputs.process_id) {
        $processId = [int] $executionOutputs.process_id
    }
    elseif ($Arguments.Contains('process_id')) {
        $processId = [int] $Arguments.process_id
    }

    if ($null -ne $processId) {
        return Get-Process -Id $processId -ErrorAction SilentlyContinue
    }

    $processName = $null
    if ($Arguments.Contains('process_name')) {
        $processName = [string] $Arguments.process_name
    }
    elseif ($Arguments.Contains('file_path')) {
        $candidateName = [System.IO.Path]::GetFileNameWithoutExtension([string] $Arguments.file_path)
        if (-not [string]::IsNullOrWhiteSpace($candidateName)) {
            $processName = $candidateName
        }
    }

    if ([string]::IsNullOrWhiteSpace($processName)) {
        return $null
    }

    return @(Get-Process -Name $processName -ErrorAction SilentlyContinue) | Select-Object -First 1
}.GetNewClosure()

return @{
    Name = 'process'
    Api = [pscustomobject]@{
        Invoke = {
            param(
                [string] $Method,
                [System.Collections.IDictionary] $Arguments = @{},
                $Prior,
                [string] $StateRoot = (Get-ParsecDefaultStateRoot),
                [System.Collections.IDictionary] $RunState = @{}
            )

            foreach ($file in @($supportFiles)) {
                . $file
            }

            switch ($Method) {
                'Capture' {
                    $process = & $resolveProcess $Arguments $null
                    if ($null -eq $process) {
                        return New-ParsecResult -Status 'Succeeded' -Message 'Captured process state: target is not running.' -Observed @{
                            is_running = $false
                        } -Outputs @{
                            captured_state = @{
                                is_running = $false
                            }
                        }
                    }

                    return New-ParsecResult -Status 'Succeeded' -Message 'Captured process state.' -Observed @{
                        process_id = [int] $process.Id
                        process_name = [string] $process.ProcessName
                        is_running = $true
                    } -Outputs @{
                        captured_state = @{
                            process_id = [int] $process.Id
                            process_name = [string] $process.ProcessName
                            is_running = $true
                        }
                    }
                }
                'Start' {
                    $process = Start-Process -FilePath $Arguments.file_path -ArgumentList @($Arguments.arguments) -PassThru
                    return New-ParsecResult -Status 'Succeeded' -Message "Started process '$($Arguments.file_path)'." -Outputs @{
                        process_id = [int] $process.Id
                        process_name = [string] $process.ProcessName
                        file_path = [string] $Arguments.file_path
                    }
                }
                'Stop' {
                    $process = & $resolveProcess $Arguments $Prior
                    if ($null -eq $process) {
                        return New-ParsecResult -Status 'Succeeded' -Message 'Process was already stopped.'
                    }

                    Stop-Process -Id $process.Id -ErrorAction SilentlyContinue

                    return New-ParsecResult -Status 'Succeeded' -Message "Stopped process id '$($process.Id)'."
                }
                'VerifyRunning' {
                    $process = & $resolveProcess $Arguments $Prior
                    if ($null -eq $process) {
                        return New-ParsecResult -Status 'Failed' -Message 'Process is not running.'
                    }

                    return New-ParsecResult -Status 'Succeeded' -Message 'Process is running.' -Observed @{
                        process_id = [int] $process.Id
                        process_name = [string] $process.ProcessName
                    }
                }
                'VerifyStopped' {
                    $process = & $resolveProcess $Arguments $Prior
                    if ($null -eq $process) {
                        return New-ParsecResult -Status 'Succeeded' -Message 'Process is stopped.'
                    }

                    return New-ParsecResult -Status 'Failed' -Message 'Process is still running.' -Observed @{
                        process_id = [int] $process.Id
                        process_name = [string] $process.ProcessName
                    }
                }
                default { throw "Process domain method '$Method' is not available." }
            }
        }.GetNewClosure()
    }
}
