function Initialize-ParsecProcessDomain {
    [CmdletBinding()]
    param()

    if (Get-Variable -Name ParsecProcessDomain -Scope Script -ErrorAction SilentlyContinue) {
        return
    }

    $script:ParsecProcessDomain = @{
        ResolveProcess = {
            param([hashtable] $Arguments, $ExecutionResult)

            $processId = $null
            if ($null -ne $ExecutionResult -and $null -ne $ExecutionResult.Outputs -and $ExecutionResult.Outputs.process_id) {
                $processId = [int] $ExecutionResult.Outputs.process_id
            }
            elseif ($Arguments.ContainsKey('process_id')) {
                $processId = [int] $Arguments.process_id
            }

            if ($null -ne $processId) {
                return Get-Process -Id $processId -ErrorAction SilentlyContinue
            }

            $processName = $null
            if ($Arguments.ContainsKey('process_name')) {
                $processName = [string] $Arguments.process_name
            }
            elseif ($Arguments.ContainsKey('file_path')) {
                $candidateName = [System.IO.Path]::GetFileNameWithoutExtension([string] $Arguments.file_path)
                if (-not [string]::IsNullOrWhiteSpace($candidateName)) {
                    $processName = $candidateName
                }
            }

            if ([string]::IsNullOrWhiteSpace($processName)) {
                return $null
            }

            return @(Get-Process -Name $processName -ErrorAction SilentlyContinue) | Select-Object -First 1
        }
        Capture = {
            param([hashtable] $Arguments)

            $process = Invoke-ParsecProcessDomain -Method 'ResolveProcess' -Arguments $Arguments
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
        Start = {
            param([hashtable] $Arguments)

            $process = Start-Process -FilePath $Arguments.file_path -ArgumentList @($Arguments.arguments) -PassThru
            return New-ParsecResult -Status 'Succeeded' -Message "Started process '$($Arguments.file_path)'." -Outputs @{
                process_id = [int] $process.Id
                process_name = [string] $process.ProcessName
                file_path = [string] $Arguments.file_path
            }
        }
        Stop = {
            param([hashtable] $Arguments, $ExecutionResult)

            $process = Invoke-ParsecProcessDomain -Method 'ResolveProcess' -Arguments $Arguments -ExecutionResult $ExecutionResult
            if ($null -eq $process) {
                return New-ParsecResult -Status 'Succeeded' -Message 'Process was already stopped.'
            }

            Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
            return New-ParsecResult -Status 'Succeeded' -Message "Stopped process id '$($process.Id)'."
        }
        VerifyRunning = {
            param([hashtable] $Arguments, $ExecutionResult)

            $process = Invoke-ParsecProcessDomain -Method 'ResolveProcess' -Arguments $Arguments -ExecutionResult $ExecutionResult
            if ($null -eq $process) {
                return New-ParsecResult -Status 'Failed' -Message 'Process is not running.'
            }

            return New-ParsecResult -Status 'Succeeded' -Message 'Process is running.' -Observed @{
                process_id = [int] $process.Id
                process_name = [string] $process.ProcessName
            }
        }
        VerifyStopped = {
            param([hashtable] $Arguments, $ExecutionResult)

            $process = Invoke-ParsecProcessDomain -Method 'ResolveProcess' -Arguments $Arguments -ExecutionResult $ExecutionResult
            if ($null -eq $process) {
                return New-ParsecResult -Status 'Succeeded' -Message 'Process is stopped.'
            }

            return New-ParsecResult -Status 'Failed' -Message 'Process is still running.' -Observed @{
                process_id = [int] $process.Id
                process_name = [string] $process.ProcessName
            }
        }
    }
}

function Invoke-ParsecProcessDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Method,

        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    Initialize-ParsecProcessDomain
    if (-not $script:ParsecProcessDomain.ContainsKey($Method)) {
        throw "Process domain method '$Method' is not available."
    }

    return & $script:ParsecProcessDomain[$Method] $Arguments $ExecutionResult
}
