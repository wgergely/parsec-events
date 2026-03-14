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

$resolveProcessLaunchMetadata = {
    param(
        $Process
    )

    if ($null -eq $Process) {
        return $null
    }

    $metadata = [ordered]@{
        process_id = [int] $Process.Id
        process_name = [string] $Process.ProcessName
        file_path = $null
        argument_line = ''
        is_running = $true
    }

    try {
        $cimProcess = Get-CimInstance -ClassName Win32_Process -Filter ("ProcessId = {0}" -f ([int] $Process.Id)) -ErrorAction Stop
        if ($null -ne $cimProcess) {
            if ($cimProcess.PSObject.Properties.Name -contains 'ExecutablePath' -and -not [string]::IsNullOrWhiteSpace([string] $cimProcess.ExecutablePath)) {
                $metadata.file_path = [string] $cimProcess.ExecutablePath
            }

            if ($cimProcess.PSObject.Properties.Name -contains 'CommandLine' -and -not [string]::IsNullOrWhiteSpace([string] $cimProcess.CommandLine)) {
                $commandLine = [string] $cimProcess.CommandLine
                if (-not [string]::IsNullOrWhiteSpace([string] $metadata.file_path)) {
                    if ($commandLine.StartsWith('"')) {
                        $closingQuote = $commandLine.IndexOf('"', 1)
                        if ($closingQuote -gt 0) {
                            $metadata.argument_line = $commandLine.Substring($closingQuote + 1).Trim()
                        }
                    }
                    elseif ($commandLine.StartsWith([string] $metadata.file_path, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $metadata.argument_line = $commandLine.Substring($metadata.file_path.Length).Trim()
                    }
                    else {
                        $metadata.argument_line = $commandLine
                    }
                }
                else {
                    $metadata.argument_line = $commandLine
                }
            }
        }
    }
    catch {
        if ($Process.PSObject.Properties.Name -contains 'Path' -and -not [string]::IsNullOrWhiteSpace([string] $Process.Path)) {
            $metadata.file_path = [string] $Process.Path
        }
    }

    return $metadata
}.GetNewClosure()

$startProcessFromState = {
    param(
        [System.Collections.IDictionary] $Arguments = @{},
        [System.Collections.IDictionary] $State = @{}
    )

    $filePath = if ($Arguments.Contains('file_path') -and -not [string]::IsNullOrWhiteSpace([string] $Arguments.file_path)) {
        [string] $Arguments.file_path
    }
    elseif ($State.Contains('file_path') -and -not [string]::IsNullOrWhiteSpace([string] $State.file_path)) {
        [string] $State.file_path
    }
    else {
        $null
    }

    if ([string]::IsNullOrWhiteSpace($filePath)) {
        return New-ParsecResult -Status 'Failed' -Message 'Process reset requires a captured file_path to restart the original process.' -Errors @('MissingCapturedState')
    }

    $argumentLine = if ($Arguments.Contains('argument_line')) {
        [string] $Arguments.argument_line
    }
    elseif ($State.Contains('argument_line')) {
        [string] $State.argument_line
    }
    else {
        $null
    }
    $argumentList = if ($Arguments.Contains('arguments')) {
        @($Arguments.arguments)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($argumentLine)) {
        $argumentLine
    }
    else {
        @()
    }

    $process = Start-Process -FilePath $filePath -ArgumentList $argumentList -PassThru
    return New-ParsecResult -Status 'Succeeded' -Message "Started process '$filePath'." -Outputs @{
        process_id = [int] $process.Id
        process_name = [string] $process.ProcessName
        file_path = $filePath
        argument_line = if (-not [string]::IsNullOrWhiteSpace($argumentLine)) { $argumentLine } else { '' }
    }
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
                                file_path = if ($Arguments.Contains('file_path')) { [string] $Arguments.file_path } else { $null }
                                argument_line = if ($Arguments.Contains('argument_line')) { [string] $Arguments.argument_line } else { '' }
                            }
                        }
                    }

                    $launchMetadata = & $resolveProcessLaunchMetadata $process
                    return New-ParsecResult -Status 'Succeeded' -Message 'Captured process state.' -Observed @{
                        process_id = [int] $process.Id
                        process_name = [string] $process.ProcessName
                        is_running = $true
                        file_path = if ($null -ne $launchMetadata -and $launchMetadata.Contains('file_path')) { $launchMetadata.file_path } else { $null }
                        argument_line = if ($null -ne $launchMetadata -and $launchMetadata.Contains('argument_line')) { $launchMetadata.argument_line } else { '' }
                    } -Outputs @{
                        captured_state = @{
                            process_id = [int] $process.Id
                            process_name = [string] $process.ProcessName
                            is_running = $true
                            file_path = if ($null -ne $launchMetadata -and $launchMetadata.Contains('file_path')) { $launchMetadata.file_path } else { $null }
                            argument_line = if ($null -ne $launchMetadata -and $launchMetadata.Contains('argument_line')) { $launchMetadata.argument_line } else { '' }
                        }
                    }
                }
                'Start' {
                    return & $startProcessFromState $Arguments @{}
                }
                'Stop' {
                    $process = & $resolveProcess $Arguments $Prior
                    if ($null -eq $process) {
                        return New-ParsecResult -Status 'Succeeded' -Message 'Process was already stopped.' -Outputs @{
                            is_running = $false
                        }
                    }

                    Stop-Process -Id $process.Id -ErrorAction SilentlyContinue

                    return New-ParsecResult -Status 'Succeeded' -Message "Stopped process id '$($process.Id)'." -Outputs @{
                        process_id = [int] $process.Id
                        process_name = [string] $process.ProcessName
                        is_running = $false
                    }
                }
                'ResetStopped' {
                    $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $Prior
                    if ($null -eq $capturedState -or -not $capturedState.Contains('is_running')) {
                        return New-ParsecResult -Status 'Failed' -Message 'Captured process state does not include a resettable running state.' -Errors @('MissingCapturedState')
                    }

                    if (-not [bool] $capturedState.is_running) {
                        return New-ParsecResult -Status 'Succeeded' -Message 'Process was already stopped before apply.'
                    }

                    return & $startProcessFromState $Arguments $capturedState
                }
                'Restart' {
                    $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $Prior
                    $process = & $resolveProcess $Arguments $Prior
                    if ($null -ne $process) {
                        $capturedState = & $resolveProcessLaunchMetadata $process
                        Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
                    }

                    return & $startProcessFromState $Arguments $(if ($null -ne $capturedState) { $capturedState } else { @{} })
                }
                'ResetRestarted' {
                    $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $Prior
                    if ($null -eq $capturedState -or -not $capturedState.Contains('is_running')) {
                        return New-ParsecResult -Status 'Failed' -Message 'Captured process state does not include a resettable running state.' -Errors @('MissingCapturedState')
                    }

                    if ([bool] $capturedState.is_running) {
                        $process = & $resolveProcess @{} $Prior
                        if ($null -ne $process) {
                            return New-ParsecResult -Status 'Succeeded' -Message 'Process was originally running and is running after restart.'
                        }

                        return & $startProcessFromState $Arguments $capturedState
                    }

                    $process = & $resolveProcess @{} $Prior
                    if ($null -eq $process) {
                        return New-ParsecResult -Status 'Succeeded' -Message 'Process was originally stopped and is now stopped.'
                    }

                    Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
                    return New-ParsecResult -Status 'Succeeded' -Message "Stopped process id '$($process.Id)'." -Outputs @{
                        process_id = [int] $process.Id
                        process_name = [string] $process.ProcessName
                        is_running = $false
                    }
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
