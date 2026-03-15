function Get-ParsecServiceDomainAdapter {
    [CmdletBinding()]
    param()

    return Get-ParsecModuleVariableValue -Name 'ParsecServiceAdapter'
}

function Resolve-ParsecServiceDomainService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Arguments
    )

    $adapter = Get-ParsecServiceDomainAdapter
    if ($null -ne $adapter -and $adapter.ContainsKey('GetService')) {
        return & $adapter.GetService $Arguments
    }

    return Get-Service -Name $Arguments.service_name -ErrorAction Stop
}

function Invoke-ParsecServiceDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Method,

        [Parameter()]
        [hashtable] $Arguments = @{}
    )

    switch ($Method) {
        'ResolveService' {
            return Resolve-ParsecServiceDomainService -Arguments $Arguments
        }
        'Capture' {
            $service = Resolve-ParsecServiceDomainService -Arguments $Arguments
            return New-ParsecResult -Status 'Succeeded' -Message "Captured service state for '$($Arguments.service_name)'." -Observed @{
                service_name = [string] $service.Name
                status = [string] $service.Status
            } -Outputs @{
                captured_state = @{
                    service_name = [string] $service.Name
                    status = [string] $service.Status
                }
            }
        }
        'Start' {
            $adapter = Get-ParsecServiceDomainAdapter
            if ($null -ne $adapter -and $adapter.ContainsKey('StartService')) {
                return & $adapter.StartService $Arguments
            }

            Start-Service -Name $Arguments.service_name
            return New-ParsecResult -Status 'Succeeded' -Message "Started service '$($Arguments.service_name)'."
        }
        'Stop' {
            $adapter = Get-ParsecServiceDomainAdapter
            if ($null -ne $adapter -and $adapter.ContainsKey('StopService')) {
                return & $adapter.StopService $Arguments
            }

            Stop-Service -Name $Arguments.service_name
            return New-ParsecResult -Status 'Succeeded' -Message "Stopped service '$($Arguments.service_name)'."
        }
        'VerifyRunning' {
            $service = Resolve-ParsecServiceDomainService -Arguments $Arguments
            if ($service.Status -eq 'Running') {
                return New-ParsecResult -Status 'Succeeded' -Message 'Service is running.' -Observed @{
                    service_name = [string] $service.Name
                    status = [string] $service.Status
                }
            }

            return New-ParsecResult -Status 'Failed' -Message "Service '$($Arguments.service_name)' is not running." -Observed @{
                service_name = [string] $service.Name
                status = [string] $service.Status
            }
        }
        'ResetStopped' {
            $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $null
            if ($null -eq $capturedState -or -not $capturedState.Contains('status')) {
                return New-ParsecResult -Status 'Failed' -Message 'Captured service state does not include a resettable status.' -Errors @('MissingCapturedState')
            }

            if ([string] $capturedState.status -ne 'Running') {
                return New-ParsecResult -Status 'Succeeded' -Message "Service was already '$([string] $capturedState.status)' before stop."
            }

            $startArgs = @{ service_name = [string] $Arguments.service_name }
            return Invoke-ParsecServiceDomain -Method 'Start' -Arguments $startArgs
        }
        'VerifyStopped' {
            $service = Resolve-ParsecServiceDomainService -Arguments $Arguments
            if ($service.Status -eq 'Stopped') {
                return New-ParsecResult -Status 'Succeeded' -Message 'Service is stopped.' -Observed @{
                    service_name = [string] $service.Name
                    status = [string] $service.Status
                }
            }

            return New-ParsecResult -Status 'Failed' -Message "Service '$($Arguments.service_name)' is still running." -Observed @{
                service_name = [string] $service.Name
                status = [string] $service.Status
            }
        }
        default {
            throw "Service domain method '$Method' is not available."
        }
    }
}
