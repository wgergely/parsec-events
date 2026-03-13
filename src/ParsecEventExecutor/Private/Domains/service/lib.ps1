function Initialize-ParsecServiceDomain {
    [CmdletBinding()]
    param()

    if (Get-Variable -Name ParsecServiceDomain -Scope Script -ErrorAction SilentlyContinue) {
        return
    }

    $script:ParsecServiceDomain = @{
        ResolveService = {
            param([hashtable] $Arguments)

            return Get-Service -Name $Arguments.service_name -ErrorAction Stop
        }
        Capture = {
            param([hashtable] $Arguments)

            $service = Invoke-ParsecServiceDomain -Method 'ResolveService' -Arguments $Arguments
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
        Start = {
            param([hashtable] $Arguments)

            Start-Service -Name $Arguments.service_name
            return New-ParsecResult -Status 'Succeeded' -Message "Started service '$($Arguments.service_name)'."
        }
        Stop = {
            param([hashtable] $Arguments)

            Stop-Service -Name $Arguments.service_name
            return New-ParsecResult -Status 'Succeeded' -Message "Stopped service '$($Arguments.service_name)'."
        }
        VerifyRunning = {
            param([hashtable] $Arguments)

            $service = Invoke-ParsecServiceDomain -Method 'ResolveService' -Arguments $Arguments
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
        VerifyStopped = {
            param([hashtable] $Arguments)

            $service = Invoke-ParsecServiceDomain -Method 'ResolveService' -Arguments $Arguments
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
    }
}

function Invoke-ParsecServiceDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Method,

        [Parameter()]
        [hashtable] $Arguments = @{}
    )

    Initialize-ParsecServiceDomain
    if (-not $script:ParsecServiceDomain.ContainsKey($Method)) {
        throw "Service domain method '$Method' is not available."
    }

    return & $script:ParsecServiceDomain[$Method] $Arguments
}
