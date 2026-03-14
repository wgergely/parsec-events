function Initialize-ParsecNvidiaAdapter {
    [CmdletBinding()]
    param()

    if ($null -ne (Get-ParsecModuleVariableValue -Name 'ParsecNvidiaAdapter')) {
        return
    }

    Set-ParsecModuleVariableValue -Name 'ParsecNvidiaAdapter' -Value @{
        GetAvailability = {
            return Get-ParsecNvidiaBackendAvailability
        }
        ResolveDisplayTarget = {
            param([hashtable] $Arguments)
            return Get-ParsecNvidiaDisplayTargetInternal -DeviceName ([string] $Arguments.device_name) -LibraryPath $(if ($Arguments.ContainsKey('library_path')) { [string] $Arguments.library_path } else { $null })
        }
        GetCustomResolutions = {
            param([hashtable] $Arguments)
            return @(Get-ParsecNvidiaCustomResolutionsInternal -DisplayId ([uint32] $Arguments.display_id) -LibraryPath $(if ($Arguments.ContainsKey('library_path')) { [string] $Arguments.library_path } else { $null }))
        }
        AddCustomResolution = {
            param([hashtable] $Arguments)
            return Add-ParsecNvidiaCustomResolutionInternal -Arguments $Arguments
        }
    } | Out-Null
}

function Invoke-ParsecNvidiaAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Method,

        [Parameter()]
        [hashtable] $Arguments = @{}
    )

    Initialize-ParsecNvidiaAdapter
    $adapter = Get-ParsecModuleVariableValue -Name 'ParsecNvidiaAdapter'
    if ($null -eq $adapter -or -not $adapter.ContainsKey($Method)) {
        throw "NVIDIA adapter method '$Method' is not available."
    }

    return & $adapter[$Method] $Arguments
}

