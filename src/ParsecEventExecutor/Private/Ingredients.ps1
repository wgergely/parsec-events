function New-ParsecIngredientDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Family,

        [Parameter(Mandatory)]
        [scriptblock] $Execute,

        [Parameter()]
        [scriptblock] $Verify,

        [Parameter()]
        [scriptblock] $Compensate,

        [Parameter()]
        [hashtable] $ArgumentSchema = @{},

        [Parameter()]
        [string] $Description = ''
    )

    return [pscustomobject]@{
        PSTypeName     = 'ParsecEventExecutor.IngredientDefinition'
        Name           = $Name
        Family         = $Family
        Description    = $Description
        ArgumentSchema = $ArgumentSchema
        Execute        = $Execute
        Verify         = $Verify
        Compensate     = $Compensate
    }
}

function Register-ParsecIngredient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Definition
    )

    $script:ParsecIngredientRegistry[$Definition.Name] = $Definition
    return $Definition
}

function Get-ParsecIngredientDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    if (-not $script:ParsecIngredientRegistry.ContainsKey($Name)) {
        throw "Ingredient '$Name' is not registered."
    }

    return $script:ParsecIngredientRegistry[$Name]
}

function Test-ParsecArgumentType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Value,

        [Parameter(Mandatory)]
        [string] $TypeName
    )

    switch ($TypeName) {
        'string' { return $Value -is [string] }
        'boolean' { return $Value -is [bool] }
        'integer' { return $Value -is [int] }
        'array' { return $Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] }
        'hashtable' { return $Value -is [System.Collections.IDictionary] }
        default { return $true }
    }
}

function Assert-ParsecIngredientArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Definition,

        [Parameter(Mandatory)]
        [hashtable] $Arguments
    )

    $schema = $Definition.ArgumentSchema
    if (-not $schema) {
        return
    }

    foreach ($required in @($schema.required)) {
        if (-not $Arguments.ContainsKey($required)) {
            throw "Ingredient '$($Definition.Name)' requires argument '$required'."
        }
    }

    foreach ($key in $schema.types.Keys) {
        if ($Arguments.ContainsKey($key) -and -not (Test-ParsecArgumentType -Value $Arguments[$key] -TypeName $schema.types[$key])) {
            throw "Ingredient '$($Definition.Name)' argument '$key' must be of type '$($schema.types[$key])'."
        }
    }
}

function Initialize-ParsecDisplayAdapter {
    [CmdletBinding()]
    param()

    if (Get-Variable -Name ParsecDisplayAdapter -Scope Script -ErrorAction SilentlyContinue) {
        return
    }

    $script:ParsecDisplayAdapter = @{
        GetObservedState = {
            Add-Type -AssemblyName System.Windows.Forms
            $screens = [System.Windows.Forms.Screen]::AllScreens
            $monitors = foreach ($screen in $screens) {
                [ordered]@{
                    device_name = $screen.DeviceName
                    is_primary  = [bool] $screen.Primary
                    enabled     = $true
                    bounds      = [ordered]@{
                        x      = $screen.Bounds.X
                        y      = $screen.Bounds.Y
                        width  = $screen.Bounds.Width
                        height = $screen.Bounds.Height
                    }
                    working_area = [ordered]@{
                        x      = $screen.WorkingArea.X
                        y      = $screen.WorkingArea.Y
                        width  = $screen.WorkingArea.Width
                        height = $screen.WorkingArea.Height
                    }
                    orientation = 'Unknown'
                }
            }

            return [ordered]@{
                captured_at      = [DateTimeOffset]::UtcNow.ToString('o')
                computer_name    = $env:COMPUTERNAME
                display_backend  = 'System.Windows.Forms.Screen'
                monitor_identity = 'device_name'
                monitors         = @($monitors)
                scaling          = [ordered]@{
                    status = 'Unsupported'
                }
            }
        }
        SetEnabled = {
            param([hashtable] $Arguments)
            return New-ParsecResult -Status 'Failed' -Message 'Display enable/disable requires a concrete backend implementation.' -Requested $Arguments -Errors @('CapabilityUnavailable')
        }
        SetPrimary = {
            param([hashtable] $Arguments)
            return New-ParsecResult -Status 'Failed' -Message 'Primary monitor changes require a concrete backend implementation.' -Requested $Arguments -Errors @('CapabilityUnavailable')
        }
        SetResolution = {
            param([hashtable] $Arguments)
            return New-ParsecResult -Status 'Failed' -Message 'Resolution changes require a concrete backend implementation.' -Requested $Arguments -Errors @('CapabilityUnavailable')
        }
        SetOrientation = {
            param([hashtable] $Arguments)
            return New-ParsecResult -Status 'Failed' -Message 'Orientation changes require a concrete backend implementation.' -Requested $Arguments -Errors @('CapabilityUnavailable')
        }
        SetScaling = {
            param([hashtable] $Arguments)
            return New-ParsecResult -Status 'Failed' -Message 'Scaling changes require a concrete backend implementation.' -Requested $Arguments -Errors @('CapabilityUnavailable')
        }
    }
}

function Invoke-ParsecDisplayAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Method,

        [Parameter()]
        [hashtable] $Arguments = @{}
    )

    Initialize-ParsecDisplayAdapter
    if (-not $script:ParsecDisplayAdapter.ContainsKey($Method)) {
        throw "Display adapter method '$Method' is not available."
    }

    return & $script:ParsecDisplayAdapter[$Method] $Arguments
}

function Get-ParsecObservedState {
    [CmdletBinding()]
    param()

    return Invoke-ParsecDisplayAdapter -Method 'GetObservedState'
}

function Compare-ParsecProfileState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ProfileDocument,

        [Parameter(Mandatory)]
        [hashtable] $ObservedState
    )

    if ($ProfileDocument.approved -eq $false) {
        return New-ParsecResult -Status 'Ambiguous' -Message 'Profile requires explicit approval before it can be verified or applied.' -Observed $ObservedState -Outputs @{ profile = $ProfileDocument }
    }

    $mismatches = New-Object System.Collections.Generic.List[string]
    foreach ($targetMonitor in @($ProfileDocument.display.monitors)) {
        $observedMonitor = @($ObservedState.monitors) | Where-Object { $_.device_name -eq $targetMonitor.device_name } | Select-Object -First 1
        if ($null -eq $observedMonitor) {
            $mismatches.Add("Monitor '$($targetMonitor.device_name)' not found.")
            continue
        }

        if ($targetMonitor.Contains('enabled') -and [bool] $targetMonitor.enabled -ne [bool] $observedMonitor.enabled) {
            $mismatches.Add("Monitor '$($targetMonitor.device_name)' enabled state mismatch.")
        }

        if ($targetMonitor.Contains('is_primary') -and [bool] $targetMonitor.is_primary -ne [bool] $observedMonitor.is_primary) {
            $mismatches.Add("Monitor '$($targetMonitor.device_name)' primary state mismatch.")
        }

        if ($targetMonitor.Contains('bounds')) {
            if ($targetMonitor.bounds.width -ne $observedMonitor.bounds.width -or $targetMonitor.bounds.height -ne $observedMonitor.bounds.height) {
                $mismatches.Add("Monitor '$($targetMonitor.device_name)' resolution mismatch.")
            }
        }

        if ($targetMonitor.Contains('orientation') -and $targetMonitor.orientation -ne 'Unknown' -and $targetMonitor.orientation -ne $observedMonitor.orientation) {
            $mismatches.Add("Monitor '$($targetMonitor.device_name)' orientation mismatch.")
        }
    }

    if ($mismatches.Count -gt 0) {
        return New-ParsecResult -Status 'Failed' -Message ($mismatches -join ' ') -Observed $ObservedState -Outputs @{ mismatches = @($mismatches) }
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Observed state matches the profile.' -Observed $ObservedState -Outputs @{ profile = $ProfileDocument }
}

function Invoke-ParsecProfileApply {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ProfileDocument
    )

    if ($ProfileDocument.approved -eq $false) {
        return New-ParsecResult -Status 'Failed' -Message 'Profile is not approved. Concrete mode values must be user approved before application.' -Outputs @{ profile = $ProfileDocument } -Errors @('ApprovalRequired')
    }

    $actions = New-Object System.Collections.Generic.List[object]
    foreach ($monitor in @($ProfileDocument.display.monitors)) {
        if ($monitor.Contains('enabled')) {
            $actions.Add((Invoke-ParsecDisplayAdapter -Method 'SetEnabled' -Arguments @{ device_name = $monitor.device_name; enabled = [bool] $monitor.enabled }))
        }

        if ($monitor.Contains('is_primary') -and [bool] $monitor.is_primary) {
            $actions.Add((Invoke-ParsecDisplayAdapter -Method 'SetPrimary' -Arguments @{ device_name = $monitor.device_name }))
        }

        if ($monitor.Contains('bounds')) {
            $actions.Add((Invoke-ParsecDisplayAdapter -Method 'SetResolution' -Arguments @{ device_name = $monitor.device_name; width = [int] $monitor.bounds.width; height = [int] $monitor.bounds.height }))
        }

        if ($monitor.Contains('orientation') -and $monitor.orientation -ne 'Unknown') {
            $actions.Add((Invoke-ParsecDisplayAdapter -Method 'SetOrientation' -Arguments @{ device_name = $monitor.device_name; orientation = $monitor.orientation }))
        }
    }

    if ($ProfileDocument.display.Contains('scaling') -and $ProfileDocument.display.scaling.Contains('value')) {
        $actions.Add((Invoke-ParsecDisplayAdapter -Method 'SetScaling' -Arguments @{ value = $ProfileDocument.display.scaling.value }))
    }

    $failures = @($actions) | Where-Object { -not (Test-ParsecSuccessfulStatus -Status $_.Status) }
    if ($failures.Count -gt 0) {
        return New-ParsecResult -Status 'Failed' -Message ($failures[0].Message) -Outputs @{ profile = $ProfileDocument; actions = @($actions) } -Errors @('ApplyFailed') -CanCompensate $false
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Profile applied successfully.' -Outputs @{ profile = $ProfileDocument; actions = @($actions) }
}

function Invoke-ParsecIngredientExecute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [hashtable] $RunState = @{}
    )

    $definition = Get-ParsecIngredientDefinition -Name $Name
    Assert-ParsecIngredientArguments -Definition $definition -Arguments $Arguments
    return & $definition.Execute $Arguments $StateRoot $RunState
}

function Invoke-ParsecIngredientVerify {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [hashtable] $RunState = @{}
    )

    $definition = Get-ParsecIngredientDefinition -Name $Name
    if ($null -eq $definition.Verify) {
        return $null
    }

    return & $definition.Verify $Arguments $ExecutionResult $StateRoot $RunState
}

function Invoke-ParsecIngredientCompensate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [hashtable] $RunState = @{}
    )

    $definition = Get-ParsecIngredientDefinition -Name $Name
    if ($null -eq $definition.Compensate) {
        return $null
    }

    return & $definition.Compensate $Arguments $ExecutionResult $StateRoot $RunState
}

function Initialize-ParsecIngredientRegistry {
    [CmdletBinding()]
    param()

    if ($script:ParsecIngredientRegistry.Count -gt 0) {
        return
    }

    Register-ParsecIngredient -Definition (New-ParsecIngredientDefinition -Name 'display.snapshot' -Family 'display' -Description 'Capture the current display state.' -Execute {
        param($Arguments, $StateRoot, $RunState)
        $observed = Get-ParsecObservedState
        return New-ParsecResult -Status 'Succeeded' -Message 'Captured current display state.' -Observed $observed -Outputs @{ observed_state = $observed }
    } -Verify {
        param($Arguments, $ExecutionResult, $StateRoot, $RunState)
        if ($null -eq $ExecutionResult.Outputs.observed_state) {
            return New-ParsecResult -Status 'Failed' -Message 'No display snapshot was produced.'
        }

        return New-ParsecResult -Status 'Succeeded' -Message 'Display snapshot is present.'
    })

    Register-ParsecIngredient -Definition (New-ParsecIngredientDefinition -Name 'display.set-enabled' -Family 'display' -Description 'Enable or disable a monitor.' -ArgumentSchema @{
        required = @('device_name', 'enabled')
        types    = @{ device_name = 'string'; enabled = 'boolean' }
    } -Execute {
        param($Arguments, $StateRoot, $RunState)
        return Invoke-ParsecDisplayAdapter -Method 'SetEnabled' -Arguments $Arguments
    })

    Register-ParsecIngredient -Definition (New-ParsecIngredientDefinition -Name 'display.set-primary' -Family 'display' -Description 'Set the primary monitor.' -ArgumentSchema @{
        required = @('device_name')
        types    = @{ device_name = 'string' }
    } -Execute {
        param($Arguments, $StateRoot, $RunState)
        return Invoke-ParsecDisplayAdapter -Method 'SetPrimary' -Arguments $Arguments
    })

    Register-ParsecIngredient -Definition (New-ParsecIngredientDefinition -Name 'display.set-resolution' -Family 'display' -Description 'Set monitor resolution.' -ArgumentSchema @{
        required = @('device_name', 'width', 'height')
        types    = @{ device_name = 'string'; width = 'integer'; height = 'integer' }
    } -Execute {
        param($Arguments, $StateRoot, $RunState)
        return Invoke-ParsecDisplayAdapter -Method 'SetResolution' -Arguments $Arguments
    })

    Register-ParsecIngredient -Definition (New-ParsecIngredientDefinition -Name 'display.set-orientation' -Family 'display' -Description 'Set monitor orientation.' -ArgumentSchema @{
        required = @('device_name', 'orientation')
        types    = @{ device_name = 'string'; orientation = 'string' }
    } -Execute {
        param($Arguments, $StateRoot, $RunState)
        return Invoke-ParsecDisplayAdapter -Method 'SetOrientation' -Arguments $Arguments
    })

    Register-ParsecIngredient -Definition (New-ParsecIngredientDefinition -Name 'display.set-scaling' -Family 'display' -Description 'Set display scaling.' -ArgumentSchema @{
        required = @('value')
        types    = @{ value = 'integer' }
    } -Execute {
        param($Arguments, $StateRoot, $RunState)
        return Invoke-ParsecDisplayAdapter -Method 'SetScaling' -Arguments $Arguments
    })

    Register-ParsecIngredient -Definition (New-ParsecIngredientDefinition -Name 'display.verify' -Family 'display' -Description 'Verify the current display state against a stored profile.' -ArgumentSchema @{
        required = @('profile_name')
        types    = @{ profile_name = 'string' }
    } -Execute {
        param($Arguments, $StateRoot, $RunState)
        $profile = Read-ParsecProfileDocument -Name $Arguments.profile_name -StateRoot $StateRoot
        $observed = Get-ParsecObservedState
        return Compare-ParsecProfileState -Profile $profile -ObservedState $observed
    })

    Register-ParsecIngredient -Definition (New-ParsecIngredientDefinition -Name 'profile.snapshot' -Family 'profile' -Description 'Capture the current observed state into a profile document.' -ArgumentSchema @{
        required = @('profile_name')
        types    = @{ profile_name = 'string'; approved = 'boolean' }
    } -Execute {
        param($Arguments, $StateRoot, $RunState)
        $observed = Get-ParsecObservedState
        $capturedProfile = [ordered]@{
            schema_version = 1
            name           = $Arguments.profile_name
            mode           = $Arguments.profile_name
            approved       = if ($Arguments.ContainsKey('approved')) { [bool] $Arguments.approved } else { $true }
            approval_status = if ($Arguments.ContainsKey('approved') -and -not [bool] $Arguments.approved) { 'Pending' } else { 'Approved' }
            source         = 'capture'
            captured_at    = [DateTimeOffset]::UtcNow.ToString('o')
            display        = $observed
            process_actions = @()
            service_actions = @()
            command_actions = @()
        }
        $path = Save-ParsecProfileDocument -Name $Arguments.profile_name -ProfileDocument $capturedProfile -StateRoot $StateRoot
        return New-ParsecResult -Status 'Succeeded' -Message "Captured profile '$($Arguments.profile_name)'." -Observed $observed -Outputs @{ profile = $capturedProfile; path = $path }
    } -Verify {
        param($Arguments, $ExecutionResult, $StateRoot, $RunState)
        $path = Get-ParsecProfileDocumentPath -Name $Arguments.profile_name -StateRoot $StateRoot
        if (-not (Test-Path -LiteralPath $path)) {
            return New-ParsecResult -Status 'Failed' -Message "Profile '$($Arguments.profile_name)' was not written."
        }

        return New-ParsecResult -Status 'Succeeded' -Message "Profile '$($Arguments.profile_name)' exists at '$path'."
    })

    Register-ParsecIngredient -Definition (New-ParsecIngredientDefinition -Name 'profile.apply' -Family 'profile' -Description 'Apply a stored profile document.' -ArgumentSchema @{
        required = @('profile_name')
        types    = @{ profile_name = 'string' }
    } -Execute {
        param($Arguments, $StateRoot, $RunState)
        $storedProfile = Read-ParsecProfileDocument -Name $Arguments.profile_name -StateRoot $StateRoot
        return Invoke-ParsecProfileApply -ProfileDocument $storedProfile
    } -Verify {
        param($Arguments, $ExecutionResult, $StateRoot, $RunState)
        $storedProfile = if ($ExecutionResult.Outputs.profile) { [hashtable] $ExecutionResult.Outputs.profile } else { Read-ParsecProfileDocument -Name $Arguments.profile_name -StateRoot $StateRoot }
        $observed = Get-ParsecObservedState
        return Compare-ParsecProfileState -ProfileDocument $storedProfile -ObservedState $observed
    })

    Register-ParsecIngredient -Definition (New-ParsecIngredientDefinition -Name 'process.start' -Family 'process' -Description 'Start a process and capture its id.' -ArgumentSchema @{
        required = @('file_path')
        types    = @{ file_path = 'string'; arguments = 'array' }
    } -Execute {
        param($Arguments, $StateRoot, $RunState)
        $process = Start-Process -FilePath $Arguments.file_path -ArgumentList @($Arguments.arguments) -PassThru
        return New-ParsecResult -Status 'Succeeded' -Message "Started process '$($Arguments.file_path)'." -Outputs @{ process_id = $process.Id; file_path = $Arguments.file_path }
    } -Verify {
        param($Arguments, $ExecutionResult, $StateRoot, $RunState)
        $process = Get-Process -Id $ExecutionResult.Outputs.process_id -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            return New-ParsecResult -Status 'Failed' -Message "Process id '$($ExecutionResult.Outputs.process_id)' is not running."
        }

        return New-ParsecResult -Status 'Succeeded' -Message 'Process is running.' -Observed @{ process_id = $process.Id; process_name = $process.ProcessName }
    } -Compensate {
        param($Arguments, $ExecutionResult, $StateRoot, $RunState)
        if ($ExecutionResult.Outputs.process_id) {
            Stop-Process -Id $ExecutionResult.Outputs.process_id -ErrorAction SilentlyContinue
            return New-ParsecResult -Status 'Succeeded' -Message "Stopped process id '$($ExecutionResult.Outputs.process_id)'." -CanCompensate $true
        }

        return New-ParsecResult -Status 'Failed' -Message 'No process id available for compensation.'
    })

    Register-ParsecIngredient -Definition (New-ParsecIngredientDefinition -Name 'process.stop' -Family 'process' -Description 'Stop a process by id or name.' -ArgumentSchema @{
        required = @()
        types    = @{ process_name = 'string'; process_id = 'integer' }
    } -Execute {
        param($Arguments, $StateRoot, $RunState)
        $stopped = @()
        if ($Arguments.ContainsKey('process_id')) {
            Stop-Process -Id $Arguments.process_id -ErrorAction Stop
            $stopped += [int] $Arguments.process_id
        }
        else {
            if (-not $Arguments.ContainsKey('process_name')) {
                throw "Ingredient 'process.stop' requires either 'process_id' or 'process_name'."
            }

            Get-Process -Name $Arguments.process_name -ErrorAction SilentlyContinue | ForEach-Object {
                Stop-Process -Id $_.Id -ErrorAction Stop
                $stopped += $_.Id
            }
        }

        return New-ParsecResult -Status 'Succeeded' -Message 'Stopped requested process target.' -Outputs @{
            stopped_ids  = @($stopped)
            process_id   = if ($Arguments.ContainsKey('process_id')) { [int] $Arguments.process_id } else { $null }
            process_name = if ($Arguments.ContainsKey('process_name')) { $Arguments.process_name } else { $null }
        }
    } -Verify {
        param($Arguments, $ExecutionResult, $StateRoot, $RunState)
        if ($Arguments.ContainsKey('process_id')) {
            $process = Get-Process -Id $Arguments.process_id -ErrorAction SilentlyContinue
            if ($null -ne $process) {
                return New-ParsecResult -Status 'Failed' -Message "Process id '$($Arguments.process_id)' is still running."
            }

            return New-ParsecResult -Status 'Succeeded' -Message "Process id '$($Arguments.process_id)' is stopped."
        }

        $processes = Get-Process -Name $Arguments.process_name -ErrorAction SilentlyContinue
        if ($null -ne $processes) {
            return New-ParsecResult -Status 'Failed' -Message "Process '$($Arguments.process_name)' is still running."
        }

        return New-ParsecResult -Status 'Succeeded' -Message "Process '$($Arguments.process_name)' is stopped."
    })

    Register-ParsecIngredient -Definition (New-ParsecIngredientDefinition -Name 'service.start' -Family 'service' -Description 'Start a Windows service.' -ArgumentSchema @{
        required = @('service_name')
        types    = @{ service_name = 'string' }
    } -Execute {
        param($Arguments, $StateRoot, $RunState)
        Start-Service -Name $Arguments.service_name -ErrorAction Stop
        return New-ParsecResult -Status 'Succeeded' -Message "Started service '$($Arguments.service_name)'." -Outputs @{ service_name = $Arguments.service_name }
    } -Verify {
        param($Arguments, $ExecutionResult, $StateRoot, $RunState)
        $service = Get-Service -Name $Arguments.service_name -ErrorAction Stop
        if ($service.Status -ne 'Running') {
            return New-ParsecResult -Status 'Failed' -Message "Service '$($Arguments.service_name)' is not running."
        }

        return New-ParsecResult -Status 'Succeeded' -Message "Service '$($Arguments.service_name)' is running."
    } -Compensate {
        param($Arguments, $ExecutionResult, $StateRoot, $RunState)
        Stop-Service -Name $Arguments.service_name -ErrorAction SilentlyContinue
        return New-ParsecResult -Status 'Succeeded' -Message "Stopped service '$($Arguments.service_name)' as compensation."
    })

    Register-ParsecIngredient -Definition (New-ParsecIngredientDefinition -Name 'service.stop' -Family 'service' -Description 'Stop a Windows service.' -ArgumentSchema @{
        required = @('service_name')
        types    = @{ service_name = 'string' }
    } -Execute {
        param($Arguments, $StateRoot, $RunState)
        Stop-Service -Name $Arguments.service_name -ErrorAction Stop
        return New-ParsecResult -Status 'Succeeded' -Message "Stopped service '$($Arguments.service_name)'." -Outputs @{ service_name = $Arguments.service_name }
    } -Verify {
        param($Arguments, $ExecutionResult, $StateRoot, $RunState)
        $service = Get-Service -Name $Arguments.service_name -ErrorAction Stop
        if ($service.Status -ne 'Stopped') {
            return New-ParsecResult -Status 'Failed' -Message "Service '$($Arguments.service_name)' is not stopped."
        }

        return New-ParsecResult -Status 'Succeeded' -Message "Service '$($Arguments.service_name)' is stopped."
    })

    Register-ParsecIngredient -Definition (New-ParsecIngredientDefinition -Name 'command.invoke' -Family 'command' -Description 'Invoke an external command with structured output capture.' -ArgumentSchema @{
        required = @('file_path')
        types    = @{ file_path = 'string'; arguments = 'array' }
    } -Execute {
        param($Arguments, $StateRoot, $RunState)
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $Arguments.file_path
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        foreach ($argument in @($Arguments.arguments)) {
            [void] $processInfo.ArgumentList.Add([string] $argument)
        }

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        [void] $process.Start()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $status = if ($process.ExitCode -eq 0) { 'Succeeded' } else { 'Failed' }
        return New-ParsecResult -Status $status -Message "Command '$($Arguments.file_path)' exited with code $($process.ExitCode)." -Outputs @{
            exit_code = $process.ExitCode
            stdout    = $stdout.TrimEnd()
            stderr    = $stderr.TrimEnd()
        }
    } -Verify {
        param($Arguments, $ExecutionResult, $StateRoot, $RunState)
        if ($ExecutionResult.Outputs.exit_code -ne 0) {
            return New-ParsecResult -Status 'Failed' -Message "Command exited with code $($ExecutionResult.Outputs.exit_code)." -Observed $ExecutionResult.Outputs
        }

        return New-ParsecResult -Status 'Succeeded' -Message 'Command completed successfully.' -Observed $ExecutionResult.Outputs
    })
}
