function Register-ParsecWatcherTask {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $TaskName = 'ParsecEventWatcher',

        [Parameter()]
        [string] $ConfigPath = (Get-ParsecWatcherDefaultConfigPath),

        [Parameter()]
        [switch] $Force
    )

    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($existingTask -and -not $Force) {
        throw "Scheduled task '$TaskName' already exists. Use -Force to replace it."
    }

    if ($existingTask -and $Force) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Information "Removed existing task '$TaskName'."
    }

    $modulePath = (Get-Module ParsecEventExecutor).Path
    if (-not $modulePath) {
        $modulePath = Join-Path -Path (Get-ParsecModuleRoot) -ChildPath 'ParsecEventExecutor.psd1'
    }

    $scriptBlock = @"
Import-Module '$modulePath' -Force
Start-ParsecWatcher -ConfigPath '$ConfigPath' -InformationAction Continue
"@

    $pwshPath = (Get-Process -Id $PID).Path

    $action = New-ScheduledTaskAction `
        -Execute $pwshPath `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$scriptBlock`""

    $trigger = New-ScheduledTaskTrigger -AtLogon

    $settings = New-ScheduledTaskSettingsSet `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -ExecutionTimeLimit (New-TimeSpan -Days 365) `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable

    $principal = New-ScheduledTaskPrincipal `
        -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
        -LogonType Interactive `
        -RunLevel Limited

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description 'Monitors Parsec log for connect/disconnect events and dispatches recipes automatically.' | Out-Null

    Write-Information "Scheduled task '$TaskName' registered. Triggers at logon with restart-on-failure (3 retries, 1-minute interval)."

    return [ordered]@{
        task_name = $TaskName
        config_path = $ConfigPath
        pwsh_path = $pwshPath
        module_path = $modulePath
        status = 'Registered'
    }
}

function Unregister-ParsecWatcherTask {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $TaskName = 'ParsecEventWatcher'
    )

    $existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $existingTask) {
        Write-Warning "Scheduled task '$TaskName' does not exist."
        return
    }

    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false

    Write-Information "Scheduled task '$TaskName' removed."

    return [ordered]@{
        task_name = $TaskName
        status = 'Removed'
    }
}
