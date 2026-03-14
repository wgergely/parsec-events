function Initialize-ParsecWindowAdapter {
    [CmdletBinding()]
    param()

    if ($null -ne (Get-ParsecModuleVariableValue -Name 'ParsecWindowAdapter')) {
        return
    }

    Set-ParsecModuleVariableValue -Name 'ParsecWindowAdapter' -Value @{
        GetForegroundWindowInfo = {
            Initialize-ParsecDisplayInterop
            return ConvertTo-ParsecPlainObject -InputObject ([ParsecEventExecutor.DisplayNative]::GetForegroundWindowCapture())
        }
        GetTopLevelWindows = {
            Initialize-ParsecDisplayInterop
            return @([ParsecEventExecutor.DisplayNative]::GetTopLevelWindows()) | ForEach-Object { ConvertTo-ParsecPlainObject -InputObject $_ }
        }
        StepAltTab = {
            Initialize-ParsecDisplayInterop
            $succeeded = [bool] [ParsecEventExecutor.DisplayNative]::StepAltTab()
            return [ordered]@{
                succeeded = $succeeded
            }
        }
        ActivateWindow = {
            param([hashtable] $Arguments)
            Initialize-ParsecDisplayInterop
            $handle = [int64] $Arguments.handle
            $succeeded = [bool] [ParsecEventExecutor.DisplayNative]::ActivateWindow($handle, [bool] $Arguments.restore_if_minimized)
            $window = ConvertTo-ParsecPlainObject -InputObject ([ParsecEventExecutor.DisplayNative]::GetForegroundWindowCapture())
            return [ordered]@{
                succeeded = $succeeded
                handle = $handle
                window = $window
            }
        }
    } | Out-Null
}

function Invoke-ParsecWindowAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Method,

        [Parameter()]
        [hashtable] $Arguments = @{}
    )

    Initialize-ParsecWindowAdapter
    $adapter = Get-ParsecModuleVariableValue -Name 'ParsecWindowAdapter'
    if ($null -eq $adapter -or -not $adapter.ContainsKey($Method)) {
        throw "Window adapter method '$Method' is not available."
    }

    return & $adapter[$Method] $Arguments
}

