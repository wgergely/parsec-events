function Initialize-ParsecDisplayInterop {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # Type is loaded via RequiredAssemblies in ParsecEventExecutor.psd1
    if (-not ('ParsecEventExecutor.DisplayNative' -as [type])) {
        throw 'ParsecEventExecutor.Native.dll is not loaded. Ensure the module is imported correctly.'
    }
}

# --- Inline C# removed: DisplayNative class is now in ParsecEventExecutor.Native.dll ---
# --- Original: ~1180 lines of Add-Type -TypeDefinition (display interop, CCD, DPI, window management) ---

function Sync-ParsecDisplayRegistryState {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Re-sync the display registry by staging ALL monitors with their current live
    # positions, then committing. This fixes stale registry state left behind by
    # prior failed CDS_UPDATEREGISTRY | CDS_NORESET operations.
    Initialize-ParsecDisplayInterop
    $observed = Get-ParsecDisplayDomainObservedState
    $stageFlags = [ParsecEventExecutor.DisplayNative]::CDS_UPDATEREGISTRY -bor [ParsecEventExecutor.DisplayNative]::CDS_NORESET

    foreach ($monitor in @($observed.monitors | Where-Object { $_.enabled })) {
        $mode = [ParsecEventExecutor.DisplayNative]::GetDeviceMode($monitor.device_name, $false)
        $result = [ParsecEventExecutor.DisplayNative]::ApplyDeviceMode($monitor.device_name, $mode, [uint32] $stageFlags)
        if ($result -ne [ParsecEventExecutor.DisplayNative]::DISP_CHANGE_SUCCESSFUL) {
            Write-Verbose "Sync-ParsecDisplayRegistryState: staging '$($monitor.device_name)' failed with code $result."
            return $false
        }
    }

    $commitResult = [ParsecEventExecutor.DisplayNative]::ApplyPendingDisplayChanges()
    if ($commitResult -ne [ParsecEventExecutor.DisplayNative]::DISP_CHANGE_SUCCESSFUL) {
        Write-Verbose "Sync-ParsecDisplayRegistryState: commit failed with code $commitResult."
    }
    return $commitResult -eq [ParsecEventExecutor.DisplayNative]::DISP_CHANGE_SUCCESSFUL
}

function Get-ParsecTextScalePercent {
    [CmdletBinding()]
    [OutputType([int])]
    param()

    try {
        $value = Get-ItemPropertyValue -Path 'HKCU:\SOFTWARE\Microsoft\Accessibility' -Name 'TextScaleFactor' -ErrorAction Stop
        if ($value -is [int] -and $value -gt 0) {
            return [int] $value
        }
    }
    catch {
        Write-Verbose "TextScaleFactor could not be read from the registry. Falling back to 100%."
    }

    return 100
}

function Get-ParsecUiScalePercent {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter()]
        [string] $DeviceName
    )

    try {
        Initialize-ParsecDisplayInterop
        if (-not [string]::IsNullOrWhiteSpace($DeviceName)) {
            return [int] [ParsecEventExecutor.DisplayNative]::GetDpiScaleForDevice($DeviceName)
        }

        return [int] [ParsecEventExecutor.DisplayNative]::GetPrimaryDpiScale()
    }
    catch {
        Write-Verbose "Native DPI scaling could not be queried. Falling back to 100%. $_"
    }

    return 100
}

function ConvertTo-ParsecLogPixels {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [int] $ScalePercent
    )

    return [int] [Math]::Round(($ScalePercent / 100.0) * 96.0)
}

function ConvertTo-ParsecOrientationName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int] $Orientation
    )

    switch ($Orientation) {
        0 { return 'Landscape' }
        1 { return 'Portrait' }
        2 { return 'LandscapeFlipped' }
        3 { return 'PortraitFlipped' }
        default { return 'Unknown' }
    }
}

function Get-ParsecScalePercent {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter()]
        [uint32] $EffectiveDpiX = 0
    )

    if ($EffectiveDpiX -le 0) {
        return $null
    }

    return [int] [Math]::Round(($EffectiveDpiX * 100.0) / 96.0)
}

function ConvertTo-ParsecDisplayConfigRotationName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int] $Rotation
    )

    switch ($Rotation) {
        1 { return 'Landscape' }
        2 { return 'Portrait' }
        3 { return 'LandscapeFlipped' }
        4 { return 'PortraitFlipped' }
        default { return 'Unknown' }
    }
}

function ConvertFrom-ParsecOrientationName {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string] $Orientation
    )

    switch ($Orientation) {
        'Landscape' { return [ParsecEventExecutor.DisplayNative]::DMDO_DEFAULT }
        'Portrait' { return [ParsecEventExecutor.DisplayNative]::DMDO_90 }
        'LandscapeFlipped' { return [ParsecEventExecutor.DisplayNative]::DMDO_180 }
        'PortraitFlipped' { return [ParsecEventExecutor.DisplayNative]::DMDO_270 }
        default { throw "Unsupported orientation '$Orientation'." }
    }
}

function Get-ParsecDisplayChangeStatusName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int] $Code
    )

    switch ($Code) {
        0 { return 'Succeeded' }
        1 { return 'RestartRequired' }
        -1 { return 'Failed' }
        -2 { return 'BadMode' }
        -3 { return 'NotUpdated' }
        -4 { return 'BadFlags' }
        -5 { return 'BadParameter' }
        -6 { return 'BadDualView' }
        default { return 'Unknown' }
    }
}

function New-ParsecDisplayChangeFailureResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Action,

        [Parameter(Mandatory)]
        [int] $Code,

        [Parameter()]
        [hashtable] $Requested = @{}
    )

    $statusName = Get-ParsecDisplayChangeStatusName -Code $Code
    $errors = @('DisplayChangeFailed', "DisplayChange::$statusName")
    $message = "Display change '$Action' failed with status '$statusName' ($Code)."
    return New-ParsecResult -Status 'Failed' -Message $message -Requested $Requested -Outputs @{
        native_status = $Code
        native_name = $statusName
        action = $Action
    } -Errors $errors
}

function Get-ParsecNativeDeviceMode {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string] $DeviceName
    )

    Initialize-ParsecDisplayInterop
    try {
        return [ParsecEventExecutor.DisplayNative]::GetDeviceMode($DeviceName, $false)
    }
    catch {
        return [ParsecEventExecutor.DisplayNative]::GetDeviceMode($DeviceName, $true)
    }
}

function Invoke-ParsecApplyDisplayMode {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $DeviceName,

        [Parameter(Mandatory)]
        $Mode,

        [Parameter()]
        [int] $Flags = 0,

        [Parameter(Mandatory)]
        [string] $Action,

        [Parameter()]
        [hashtable] $Requested = @{}
    )

    Initialize-ParsecDisplayInterop

    $testResult = [ParsecEventExecutor.DisplayNative]::ApplyDeviceMode($DeviceName, $Mode, [uint32] ([ParsecEventExecutor.DisplayNative]::CDS_TEST -bor $Flags))
    if ($testResult -ne [ParsecEventExecutor.DisplayNative]::DISP_CHANGE_SUCCESSFUL) {
        return New-ParsecDisplayChangeFailureResult -Action "${Action}:test" -Code $testResult -Requested $Requested
    }

    $stageFlags = [ParsecEventExecutor.DisplayNative]::CDS_UPDATEREGISTRY -bor [ParsecEventExecutor.DisplayNative]::CDS_NORESET -bor $Flags
    $stageResult = [ParsecEventExecutor.DisplayNative]::ApplyDeviceMode($DeviceName, $Mode, [uint32] $stageFlags)
    if ($stageResult -ne [ParsecEventExecutor.DisplayNative]::DISP_CHANGE_SUCCESSFUL) {
        return New-ParsecDisplayChangeFailureResult -Action "${Action}:stage" -Code $stageResult -Requested $Requested
    }

    $commitResult = [ParsecEventExecutor.DisplayNative]::ApplyPendingDisplayChanges()
    if ($commitResult -ne [ParsecEventExecutor.DisplayNative]::DISP_CHANGE_SUCCESSFUL) {
        return New-ParsecDisplayChangeFailureResult -Action "${Action}:commit" -Code $commitResult -Requested $Requested
    }

    return New-ParsecResult -Status 'Succeeded' -Message "Display change '$Action' applied." -Requested $Requested -Outputs @{
        native_status = 0
        native_name = 'Succeeded'
        action = $Action
    }
}

function Set-ParsecDisplayResolutionInternal {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Arguments
    )

    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments

    $mode = Get-ParsecNativeDeviceMode -DeviceName $deviceName
    $mode.dmPelsWidth = [int] $Arguments.width
    $mode.dmPelsHeight = [int] $Arguments.height
    # Set only width+height fields; clear frequency so the driver picks the best
    # matching refresh rate. Inheriting the current frequency causes BadMode when
    # switching between resolutions with different supported refresh rates
    # (e.g., 1920x1080@59Hz → 3000x2000 which only supports 60Hz).
    $mode.dmFields = [ParsecEventExecutor.DisplayNative]::DM_PELSWIDTH -bor [ParsecEventExecutor.DisplayNative]::DM_PELSHEIGHT

    $result = Invoke-ParsecApplyDisplayMode -DeviceName $deviceName -Mode $mode -Action 'SetResolution' -Requested $Arguments
    if ($result.Status -eq 'Succeeded') {
        $result.Message = "Set resolution for '$deviceName' to $($Arguments.width)x$($Arguments.height)."
    }

    return $result
}

function Set-ParsecDisplayOrientationInternal {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Arguments
    )

    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments

    $mode = Get-ParsecNativeDeviceMode -DeviceName $deviceName
    $currentOrientation = [int] $mode.dmDisplayOrientation
    $targetOrientation = ConvertFrom-ParsecOrientationName -Orientation ([string] $Arguments.orientation)

    $currentIsPortrait = $currentOrientation -in @([ParsecEventExecutor.DisplayNative]::DMDO_90, [ParsecEventExecutor.DisplayNative]::DMDO_270)
    $targetIsPortrait = $targetOrientation -in @([ParsecEventExecutor.DisplayNative]::DMDO_90, [ParsecEventExecutor.DisplayNative]::DMDO_270)
    if ($currentIsPortrait -ne $targetIsPortrait) {
        $width = $mode.dmPelsWidth
        $mode.dmPelsWidth = $mode.dmPelsHeight
        $mode.dmPelsHeight = $width
        $mode.dmFields = $mode.dmFields -bor [ParsecEventExecutor.DisplayNative]::DM_PELSWIDTH -bor [ParsecEventExecutor.DisplayNative]::DM_PELSHEIGHT
    }

    $mode.dmDisplayOrientation = $targetOrientation
    $mode.dmFields = $mode.dmFields -bor [ParsecEventExecutor.DisplayNative]::DM_DISPLAYORIENTATION

    $result = Invoke-ParsecApplyDisplayMode -DeviceName $deviceName -Mode $mode -Action 'SetOrientation' -Requested $Arguments
    if ($result.Status -eq 'Succeeded') {
        $result.Message = "Set orientation for '$deviceName' to '$($Arguments.orientation)'."
    }

    return $result
}

function Set-ParsecDisplayEnabledInternal {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Arguments
    )

    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments
    $enable = [bool] $Arguments.enabled

    $mode = Get-ParsecNativeDeviceMode -DeviceName $deviceName

    if ($enable) {
        $bounds = if ($Arguments.ContainsKey('bounds') -and $Arguments.bounds -is [System.Collections.IDictionary]) {
            ConvertTo-ParsecPlainObject -InputObject $Arguments.bounds
        }
        else {
            $null
        }

        $width = if ($null -ne $bounds -and $bounds.Contains('width')) { [int] $bounds.width } else { [int] $mode.dmPelsWidth }
        $height = if ($null -ne $bounds -and $bounds.Contains('height')) { [int] $bounds.height } else { [int] $mode.dmPelsHeight }
        if ($width -le 0 -or $height -le 0) {
            return New-ParsecResult -Status 'Failed' -Message "Cannot enable '$deviceName' without width and height." -Requested $Arguments -Errors @('MissingCapturedState')
        }

        $mode.dmPelsWidth = $width
        $mode.dmPelsHeight = $height
        if ($null -ne $bounds) {
            if ($bounds.Contains('x')) { $mode.dmPositionX = [int] $bounds.x }
            if ($bounds.Contains('y')) { $mode.dmPositionY = [int] $bounds.y }
        }

        $mode.dmFields = $mode.dmFields -bor [ParsecEventExecutor.DisplayNative]::DM_POSITION -bor [ParsecEventExecutor.DisplayNative]::DM_PELSWIDTH -bor [ParsecEventExecutor.DisplayNative]::DM_PELSHEIGHT
    }
    else {
        $mode.dmPelsWidth = 0
        $mode.dmPelsHeight = 0
        $mode.dmFields = $mode.dmFields -bor [ParsecEventExecutor.DisplayNative]::DM_POSITION -bor [ParsecEventExecutor.DisplayNative]::DM_PELSWIDTH -bor [ParsecEventExecutor.DisplayNative]::DM_PELSHEIGHT
    }

    $result = Invoke-ParsecApplyDisplayMode -DeviceName $deviceName -Mode $mode -Action 'SetEnabled' -Requested $Arguments
    if ($result.Status -eq 'Succeeded') {
        $stateLabel = if ($enable) { 'enabled' } else { 'disabled' }
        $result.Message = "Monitor '$deviceName' $stateLabel."
    }

    return $result
}

function Set-ParsecDisplayPrimaryInternal {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Arguments
    )

    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments
    Initialize-ParsecDisplayInterop

    # Re-sync display registry before staging to recover from any prior dirty state
    Sync-ParsecDisplayRegistryState | Out-Null

    # Get current observed state to find the existing primary and compute position offsets
    $observed = Get-ParsecDisplayDomainObservedState
    $currentPrimary = @($observed.monitors | Where-Object { $_.is_primary }) | Select-Object -First 1
    $targetMonitor = @($observed.monitors | Where-Object { $_.device_name -eq $deviceName }) | Select-Object -First 1

    if ($null -eq $targetMonitor) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' not found." -Requested $Arguments -Errors @('MonitorNotFound')
    }

    if ($null -ne $currentPrimary -and $currentPrimary.device_name -eq $deviceName -and -not $Arguments.ContainsKey('positions')) {
        return New-ParsecResult -Status 'Succeeded' -Message "Monitor '$deviceName' is already primary." -Requested $Arguments
    }

    # Per Microsoft docs and Raymond Chen's guidance, setting primary requires:
    # 1. Stage each monitor with its new position using CDS_UPDATEREGISTRY | CDS_NORESET
    # 2. Stage new primary at (0,0) with CDS_SET_PRIMARY | CDS_UPDATEREGISTRY | CDS_NORESET
    # 3. Commit with ChangeDisplaySettingsEx(null, null, null, 0, null)
    #
    # When 'positions' is present (from a reset operation), restore exact captured positions.
    # Otherwise, compute positions by translating all monitors so the target ends up at (0,0).
    #
    # Sources:
    # https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-changedisplaysettingsexw
    # https://devblogs.microsoft.com/oldnewthing/20211222-00/?p=106048

    $stageFlags = [ParsecEventExecutor.DisplayNative]::CDS_UPDATEREGISTRY -bor [ParsecEventExecutor.DisplayNative]::CDS_NORESET

    # Determine whether to use exact positions (reset) or compute offsets (apply)
    $useExactPositions = $Arguments.ContainsKey('positions') -and @($Arguments.positions).Count -gt 0

    # Step 1: Stage new primary at (0,0) with CDS_SET_PRIMARY FIRST.
    # Windows rejects repositioning the current primary away from (0,0) until a new
    # primary is designated, so the primary designation must be staged before repositioning.
    $mode = Get-ParsecNativeDeviceMode -DeviceName $deviceName
    if ($useExactPositions) {
        $positionIndex = @{}
        foreach ($pos in @($Arguments.positions)) {
            $positionIndex[[string] $pos.device_name] = $pos
        }
        $targetPos = $positionIndex[$deviceName]
        $mode.dmPositionX = if ($null -ne $targetPos) { [int] $targetPos.x } else { 0 }
        $mode.dmPositionY = if ($null -ne $targetPos) { [int] $targetPos.y } else { 0 }
    }
    else {
        $mode.dmPositionX = 0
        $mode.dmPositionY = 0
    }
    $mode.dmFields = $mode.dmFields -bor [ParsecEventExecutor.DisplayNative]::DM_POSITION
    $primaryFlags = $stageFlags -bor [ParsecEventExecutor.DisplayNative]::CDS_SET_PRIMARY
    $stageResult = [ParsecEventExecutor.DisplayNative]::ApplyDeviceMode($deviceName, $mode, [uint32] $primaryFlags)
    if ($stageResult -ne [ParsecEventExecutor.DisplayNative]::DISP_CHANGE_SUCCESSFUL) {
        return New-ParsecDisplayChangeFailureResult -Action 'SetPrimary:stage' -Code $stageResult -Requested $Arguments
    }

    # Step 2: Reposition all other monitors
    if ($useExactPositions) {
        foreach ($monitor in @($observed.monitors | Where-Object { $_.enabled -and $_.device_name -ne $deviceName })) {
            $otherMode = Get-ParsecNativeDeviceMode -DeviceName $monitor.device_name
            if ($null -eq $otherMode) { continue }

            $savedPos = $positionIndex[[string] $monitor.device_name]
            if ($null -eq $savedPos) {
                return New-ParsecResult -Status 'Failed' -Message "Captured positions missing entry for '$($monitor.device_name)'." -Requested $Arguments -Errors @('IncompleteCapturedPositions')
            }
            $otherMode.dmPositionX = [int] $savedPos.x
            $otherMode.dmPositionY = [int] $savedPos.y
            $otherMode.dmFields = $otherMode.dmFields -bor [ParsecEventExecutor.DisplayNative]::DM_POSITION

            $otherResult = [ParsecEventExecutor.DisplayNative]::ApplyDeviceMode($monitor.device_name, $otherMode, [uint32] $stageFlags)
            if ($otherResult -ne [ParsecEventExecutor.DisplayNative]::DISP_CHANGE_SUCCESSFUL) {
                return New-ParsecDisplayChangeFailureResult -Action 'SetPrimary:reposition' -Code $otherResult -Requested $Arguments
            }
        }
    }
    else {
        $offsetX = [int] $targetMonitor.bounds.x
        $offsetY = [int] $targetMonitor.bounds.y

        foreach ($monitor in @($observed.monitors | Where-Object { $_.enabled -and $_.device_name -ne $deviceName })) {
            $otherMode = Get-ParsecNativeDeviceMode -DeviceName $monitor.device_name
            if ($null -eq $otherMode) { continue }

            $otherMode.dmPositionX = [int] $monitor.bounds.x - $offsetX
            $otherMode.dmPositionY = [int] $monitor.bounds.y - $offsetY
            $otherMode.dmFields = $otherMode.dmFields -bor [ParsecEventExecutor.DisplayNative]::DM_POSITION

            $otherResult = [ParsecEventExecutor.DisplayNative]::ApplyDeviceMode($monitor.device_name, $otherMode, [uint32] $stageFlags)
            if ($otherResult -ne [ParsecEventExecutor.DisplayNative]::DISP_CHANGE_SUCCESSFUL) {
                return New-ParsecDisplayChangeFailureResult -Action 'SetPrimary:reposition' -Code $otherResult -Requested $Arguments
            }
        }
    }

    # Step 3: Commit all pending changes
    $commitResult = [ParsecEventExecutor.DisplayNative]::ApplyPendingDisplayChanges()
    if ($commitResult -ne [ParsecEventExecutor.DisplayNative]::DISP_CHANGE_SUCCESSFUL) {
        return New-ParsecDisplayChangeFailureResult -Action 'SetPrimary:commit' -Code $commitResult -Requested $Arguments
    }

    return New-ParsecResult -Status 'Succeeded' -Message "Monitor '$deviceName' set as primary." -Requested $Arguments
}


function Get-ParsecDisplayIdentityKey {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [psobject] $DisplayPath
    )

    if (-not [string]::IsNullOrWhiteSpace([string] $DisplayPath.SourceDeviceName)) {
        return 'source:{0}' -f ([string] $DisplayPath.SourceDeviceName)
    }

    if (-not [string]::IsNullOrWhiteSpace([string] $DisplayPath.MonitorDevicePath)) {
        return 'monitor-path:{0}' -f ([string] $DisplayPath.MonitorDevicePath)
    }

    return 'target:{0}|{1}|{2}' -f ([string] $DisplayPath.AdapterKey), ([int] $DisplayPath.SourceId), ([int] $DisplayPath.TargetId)
}

function Get-ParsecDisplayCaptureState {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    try {
        Initialize-ParsecDisplayInterop
        $displayPaths = @([ParsecEventExecutor.DisplayNative]::GetDisplayConfigPaths())
        $nativeMonitors = [ParsecEventExecutor.DisplayNative]::GetCurrentMonitors()
        $textScalePercent = Get-ParsecTextScalePercent
        $uiScalePercent = Get-ParsecUiScalePercent
        $themeState = Invoke-ParsecPersonalizationAdapter -Method 'GetThemeState'
        $wallpaperState = Invoke-ParsecPersonalizationAdapter -Method 'GetWallpaperState'
        $nativeMonitorIndex = @{}
        foreach ($monitor in @($nativeMonitors)) {
            $nativeMonitorIndex[[string] $monitor.DeviceName] = $monitor
        }

        $topologyPaths = foreach ($path in @($displayPaths)) {
            [ordered]@{
                adapter_id = [string] $path.AdapterKey
                source_id = [int] $path.SourceId
                target_id = [int] $path.TargetId
                source_name = [string] $path.SourceDeviceName
                friendly_name = [string] $path.MonitorFriendlyName
                monitor_device_path = [string] $path.MonitorDevicePath
                adapter_device_path = [string] $path.AdapterDevicePath
                is_active = [bool] $path.IsActive
                target_available = [bool] $path.TargetAvailable
                rotation = [int] $path.Rotation
                scaling = [int] $path.Scaling
                output_technology = [int] $path.OutputTechnology
                scan_line_ordering = [int] $path.ScanLineOrdering
                refresh_rate = [ordered]@{
                    numerator = [int] $path.RefreshRateNumerator
                    denominator = [int] $path.RefreshRateDenominator
                }
                path_flags = [int] $path.PathFlags
                source_status_flags = [int] $path.SourceStatusFlags
                target_status_flags = [int] $path.TargetStatusFlags
                source_mode = [ordered]@{
                    available = [bool] $path.HasSourceMode
                    width = if ($path.HasSourceMode) { [int] $path.SourceWidth } else { $null }
                    height = if ($path.HasSourceMode) { [int] $path.SourceHeight } else { $null }
                    position_x = if ($path.HasSourceMode) { [int] $path.SourcePositionX } else { $null }
                    position_y = if ($path.HasSourceMode) { [int] $path.SourcePositionY } else { $null }
                    pixel_format = if ($path.HasSourceMode) { [int] $path.PixelFormat } else { $null }
                }
                target_mode = [ordered]@{
                    available = [bool] $path.HasTargetMode
                    width = if ($path.HasTargetMode) { [int] $path.TargetWidth } else { $null }
                    height = if ($path.HasTargetMode) { [int] $path.TargetHeight } else { $null }
                    pixel_rate = if ($path.HasTargetMode) { [uint64] $path.PixelRate } else { $null }
                }
            }
        }

        $selectedDisplayPaths = [ordered]@{}
        $meaningfulDisplayPaths = foreach ($path in @($displayPaths)) {
            if (
                $path.IsActive -or
                $path.TargetAvailable -or
                -not [string]::IsNullOrWhiteSpace([string] $path.MonitorDevicePath) -or
                -not [string]::IsNullOrWhiteSpace([string] $path.MonitorFriendlyName)
            ) {
                $path
            }
        }

        $sortedDisplayPaths = @($meaningfulDisplayPaths) | Sort-Object `
        @{ Expression = { if ($_.IsActive) { 0 } else { 1 } } }, `
        @{ Expression = { if ($_.TargetAvailable) { 0 } else { 1 } } }, `
        @{ Expression = { if ($_.HasSourceMode) { 0 } else { 1 } } }, `
        @{ Expression = { if (-not [string]::IsNullOrWhiteSpace([string] $_.MonitorDevicePath)) { 0 } else { 1 } } }, `
        @{ Expression = { [string] $_.SourceDeviceName } }, `
        @{ Expression = { [int] $_.TargetId } }

        foreach ($path in $sortedDisplayPaths) {
            $identityKey = Get-ParsecDisplayIdentityKey -DisplayPath $path
            if (-not $selectedDisplayPaths.Contains($identityKey)) {
                $selectedDisplayPaths[$identityKey] = $path
            }
        }

        $monitors = foreach ($path in $selectedDisplayPaths.Values) {
            $deviceName = if (-not [string]::IsNullOrWhiteSpace([string] $path.SourceDeviceName)) {
                [string] $path.SourceDeviceName
            }
            elseif (-not [string]::IsNullOrWhiteSpace([string] $path.MonitorFriendlyName)) {
                [string] $path.MonitorFriendlyName
            }
            else {
                '{0}:{1}' -f $path.AdapterKey, $path.TargetId
            }

            $nativeMonitor = if ($nativeMonitorIndex.ContainsKey($deviceName)) { $nativeMonitorIndex[$deviceName] } else { $null }
            $scalePercent = $null
            if ([bool] $path.IsActive -and -not [string]::IsNullOrWhiteSpace($deviceName)) {
                try {
                    $scalePercent = Get-ParsecUiScalePercent -DeviceName $deviceName
                }
                catch {
                    $scalePercent = $null
                }
            }

            if ($null -eq $scalePercent -and $null -ne $nativeMonitor -and $nativeMonitor.HasEffectiveDpi) {
                $scalePercent = Get-ParsecScalePercent -EffectiveDpiX $nativeMonitor.EffectiveDpiX
            }
            $refreshRate = if ($path.RefreshRateDenominator -gt 0) { [int] [Math]::Round($path.RefreshRateNumerator / $path.RefreshRateDenominator) } elseif ($null -ne $nativeMonitor) { [int] $nativeMonitor.DisplayFrequency } else { $null }
            $width = if ($path.HasSourceMode) { [int] $path.SourceWidth } elseif ($path.HasTargetMode) { [int] $path.TargetWidth } elseif ($null -ne $nativeMonitor) { [int] $nativeMonitor.Width } else { $null }
            $height = if ($path.HasSourceMode) { [int] $path.SourceHeight } elseif ($path.HasTargetMode) { [int] $path.TargetHeight } elseif ($null -ne $nativeMonitor) { [int] $nativeMonitor.Height } else { $null }
            $x = if ($path.HasSourceMode) { [int] $path.SourcePositionX } elseif ($null -ne $nativeMonitor) { [int] $nativeMonitor.Left } else { $null }
            $y = if ($path.HasSourceMode) { [int] $path.SourcePositionY } elseif ($null -ne $nativeMonitor) { [int] $nativeMonitor.Top } else { $null }

            [ordered]@{
                device_name = $deviceName
                source_name = [string] $path.SourceDeviceName
                friendly_name = [string] $path.MonitorFriendlyName
                monitor_device_path = [string] $path.MonitorDevicePath
                adapter_device_path = [string] $path.AdapterDevicePath
                adapter_id = [string] $path.AdapterKey
                source_id = [int] $path.SourceId
                target_id = [int] $path.TargetId
                is_primary = if ($null -ne $nativeMonitor) { [bool] $nativeMonitor.IsPrimary } else { $false }
                enabled = [bool] $path.IsActive
                target_available = [bool] $path.TargetAvailable
                bounds = [ordered]@{
                    x = $x
                    y = $y
                    width = $width
                    height = $height
                }
                working_area = [ordered]@{
                    x = if ($null -ne $nativeMonitor) { [int] $nativeMonitor.WorkLeft } else { $null }
                    y = if ($null -ne $nativeMonitor) { [int] $nativeMonitor.WorkTop } else { $null }
                    width = if ($null -ne $nativeMonitor) { [int] $nativeMonitor.WorkWidth } else { $null }
                    height = if ($null -ne $nativeMonitor) { [int] $nativeMonitor.WorkHeight } else { $null }
                }
                orientation = ConvertTo-ParsecDisplayConfigRotationName -Rotation ([int] $path.Rotation)
                display = [ordered]@{
                    width = $width
                    height = $height
                    bits_per_pel = if ($null -ne $nativeMonitor) { [int] $nativeMonitor.BitsPerPel } else { $null }
                    refresh_rate_hz = $refreshRate
                    effective_dpi_x = if ($null -ne $nativeMonitor -and $nativeMonitor.HasEffectiveDpi) { [int] $nativeMonitor.EffectiveDpiX } else { $null }
                    effective_dpi_y = if ($null -ne $nativeMonitor -and $nativeMonitor.HasEffectiveDpi) { [int] $nativeMonitor.EffectiveDpiY } else { $null }
                    scale_percent = $scalePercent
                    text_scale_percent = [int] $textScalePercent
                }
                identity = [ordered]@{
                    scheme = 'adapter_id+target_id'
                    adapter_id = [string] $path.AdapterKey
                    source_id = [int] $path.SourceId
                    target_id = [int] $path.TargetId
                    source_name = [string] $path.SourceDeviceName
                    monitor_device_path = [string] $path.MonitorDevicePath
                }
                topology = [ordered]@{
                    is_active = [bool] $path.IsActive
                    target_available = [bool] $path.TargetAvailable
                    path_flags = [int] $path.PathFlags
                    source_status_flags = [int] $path.SourceStatusFlags
                    target_status_flags = [int] $path.TargetStatusFlags
                    output_technology = [int] $path.OutputTechnology
                    scaling_mode = [int] $path.Scaling
                    scan_line_ordering = [int] $path.ScanLineOrdering
                    source_mode = [ordered]@{
                        available = [bool] $path.HasSourceMode
                        width = if ($path.HasSourceMode) { [int] $path.SourceWidth } else { $null }
                        height = if ($path.HasSourceMode) { [int] $path.SourceHeight } else { $null }
                        position_x = if ($path.HasSourceMode) { [int] $path.SourcePositionX } else { $null }
                        position_y = if ($path.HasSourceMode) { [int] $path.SourcePositionY } else { $null }
                        pixel_format = if ($path.HasSourceMode) { [int] $path.PixelFormat } else { $null }
                    }
                    target_mode = [ordered]@{
                        available = [bool] $path.HasTargetMode
                        width = if ($path.HasTargetMode) { [int] $path.TargetWidth } else { $null }
                        height = if ($path.HasTargetMode) { [int] $path.TargetHeight } else { $null }
                        pixel_rate = if ($path.HasTargetMode) { [uint64] $path.PixelRate } else { $null }
                    }
                }
            }
        }

        return [ordered]@{
            captured_at = [DateTimeOffset]::UtcNow.ToString('o')
            computer_name = $env:COMPUTERNAME
            display_backend = 'CCD.QueryDisplayConfig+Win32.EnumDisplaySettings'
            monitor_identity = 'adapter_id+target_id'
            monitors = @($monitors)
            topology = [ordered]@{
                query_mode = 'QDC_ALL_PATHS'
                path_count = @($displayPaths).Count
                paths = @($topologyPaths)
            }
            scaling = [ordered]@{
                status = 'Captured'
                ui_scale_percent = [int] $uiScalePercent
                text_scale_percent = [int] $textScalePercent
                monitors = @(
                    foreach ($monitor in @($monitors)) {
                        [ordered]@{
                            device_name = [string] $monitor.device_name
                            scale_percent = $monitor.display.scale_percent
                            effective_dpi_x = $monitor.display.effective_dpi_x
                            effective_dpi_y = $monitor.display.effective_dpi_y
                            text_scale_percent = [int] $textScalePercent
                        }
                    }
                )
            }
            font_scaling = [ordered]@{
                text_scale_percent = [int] $textScalePercent
            }
            theme = $themeState
            wallpaper = $wallpaperState
        }
    }
    catch {
        Add-Type -AssemblyName System.Windows.Forms
        $screens = [System.Windows.Forms.Screen]::AllScreens
        $textScalePercent = Get-ParsecTextScalePercent
        $uiScalePercent = Get-ParsecUiScalePercent
        $themeState = Invoke-ParsecPersonalizationAdapter -Method 'GetThemeState'
        $wallpaperState = Invoke-ParsecPersonalizationAdapter -Method 'GetWallpaperState'
        $monitors = foreach ($screen in $screens) {
            [ordered]@{
                device_name = $screen.DeviceName
                is_primary = [bool] $screen.Primary
                enabled = $true
                bounds = [ordered]@{
                    x = $screen.Bounds.X
                    y = $screen.Bounds.Y
                    width = $screen.Bounds.Width
                    height = $screen.Bounds.Height
                }
                working_area = [ordered]@{
                    x = $screen.WorkingArea.X
                    y = $screen.WorkingArea.Y
                    width = $screen.WorkingArea.Width
                    height = $screen.WorkingArea.Height
                }
                orientation = if ($screen.Bounds.Height -gt $screen.Bounds.Width) { 'Portrait' } else { 'Landscape' }
                display = [ordered]@{
                    width = $screen.Bounds.Width
                    height = $screen.Bounds.Height
                    bits_per_pel = $null
                    refresh_rate_hz = $null
                    effective_dpi_x = $null
                    effective_dpi_y = $null
                    scale_percent = $null
                    text_scale_percent = [int] $textScalePercent
                }
            }
        }

        return [ordered]@{
            captured_at = [DateTimeOffset]::UtcNow.ToString('o')
            computer_name = $env:COMPUTERNAME
            display_backend = 'System.Windows.Forms.Screen'
            monitor_identity = 'device_name'
            monitors = @($monitors)
            topology = [ordered]@{
                query_mode = 'Fallback'
                path_count = 0
                paths = @()
            }
            scaling = [ordered]@{
                status = 'Partial'
                ui_scale_percent = [int] $uiScalePercent
                text_scale_percent = [int] $textScalePercent
                monitors = @()
            }
            font_scaling = [ordered]@{
                text_scale_percent = [int] $textScalePercent
            }
            theme = $themeState
            wallpaper = $wallpaperState
        }
    }
}


function Compare-ParsecActiveDisplaySelectionState {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $TargetState,

        [Parameter(Mandatory)]
        [hashtable] $ObservedState
    )

    $mismatches = New-Object System.Collections.Generic.List[string]
    $targetEnabled = @($TargetState.monitors | Where-Object { [bool] $_.enabled } | ForEach-Object { [string] $_.device_name })
    $observedEnabled = @($ObservedState.monitors | Where-Object { [bool] $_.enabled } | ForEach-Object { [string] $_.device_name })
    $targetPrimary = @($TargetState.monitors | Where-Object { [bool] $_.enabled -and [bool] $_.is_primary } | Select-Object -First 1)
    $observedPrimary = @($ObservedState.monitors | Where-Object { [bool] $_.enabled -and [bool] $_.is_primary } | Select-Object -First 1)

    $targetEnabledSet = @($targetEnabled | Sort-Object -Unique)
    $observedEnabledSet = @($observedEnabled | Sort-Object -Unique)
    if ((ConvertTo-Json $targetEnabledSet -Compress) -cne (ConvertTo-Json $observedEnabledSet -Compress)) {
        $mismatches.Add('Enabled display set mismatch.')
    }

    if ($targetPrimary.Count -eq 0) {
        $mismatches.Add('Target state does not define a primary active display.')
    }
    elseif ($observedPrimary.Count -eq 0) {
        $mismatches.Add('Observed state does not define a primary active display.')
    }
    elseif ([string] $targetPrimary[0].device_name -ne [string] $observedPrimary[0].device_name) {
        $mismatches.Add("Primary display mismatch. Expected '$($targetPrimary[0].device_name)' but observed '$($observedPrimary[0].device_name)'.")
    }

    if ($mismatches.Count -gt 0) {
        return New-ParsecResult -Status 'Failed' -Message ($mismatches -join ' ') -Observed $ObservedState -Outputs @{
            mismatches = @($mismatches)
            target_state = $TargetState
            target_enabled = $targetEnabledSet
            observed_enabled = $observedEnabledSet
        }
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Observed active display selection matches the target state.' -Observed $ObservedState -Outputs @{
        target_state = $TargetState
        target_enabled = $targetEnabledSet
        observed_enabled = $observedEnabledSet
    }
}

function Resolve-ParsecActiveDisplayTargetState {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ObservedState,

        [Parameter(Mandatory)]
        [hashtable] $Arguments,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $requestedScreenIds = @($Arguments.screen_ids)
    if ($requestedScreenIds.Count -eq 0) {
        return New-ParsecResult -Status 'Failed' -Message 'set-activedisplays requires at least one screen id.' -Observed $ObservedState -Errors @('MissingScreenIds')
    }

    $requestedMonitors = New-Object System.Collections.Generic.List[object]
    $requestedIdentityKeys = New-Object System.Collections.Generic.HashSet[string]
    $requestedDeviceNames = New-Object System.Collections.Generic.HashSet[string]
    foreach ($screenId in $requestedScreenIds) {
        $monitor = Resolve-ParsecDisplayDomainMonitorByScreenId -ObservedState $ObservedState -ScreenId ([int] $screenId) -StateRoot $StateRoot
        if ($null -eq $monitor) {
            return New-ParsecResult -Status 'Failed' -Message "Screen id '$screenId' could not be resolved." -Observed $ObservedState -Errors @('MonitorNotFound')
        }

        $identityKey = Get-ParsecDisplayDomainIdentityKey -Monitor $monitor
        if (-not $requestedIdentityKeys.Add($identityKey)) {
            return New-ParsecResult -Status 'Failed' -Message "Screen id '$screenId' resolves to a duplicate display target." -Observed $ObservedState -Errors @('DuplicateScreenId')
        }

        if ($monitor.Contains('target_available') -and $null -ne $monitor.target_available -and -not [bool] $monitor.target_available) {
            return New-ParsecResult -Status 'Failed' -Message "Screen id '$screenId' is not currently target-available." -Observed $ObservedState -Errors @('TargetUnavailable')
        }

        $requestedMonitors.Add($monitor)
        $requestedDeviceNames.Add([string] $monitor.device_name) | Out-Null
    }

    $primaryMonitor = @($requestedMonitors | ForEach-Object { $_ } | Where-Object { [bool] $_.is_primary }) | Select-Object -First 1
    if ($null -eq $primaryMonitor) {
        $primaryMonitor = $requestedMonitors[0]
    }

    $primaryOffsetX = if ($primaryMonitor.Contains('bounds') -and $primaryMonitor.bounds -is [System.Collections.IDictionary] -and $null -ne $primaryMonitor.bounds.x) {
        [int] $primaryMonitor.bounds.x
    }
    else {
        0
    }
    $primaryOffsetY = if ($primaryMonitor.Contains('bounds') -and $primaryMonitor.bounds -is [System.Collections.IDictionary] -and $null -ne $primaryMonitor.bounds.y) {
        [int] $primaryMonitor.bounds.y
    }
    else {
        0
    }

    $targetState = Get-ParsecDisplayDomainTopologyCaptureState -ObservedState $ObservedState
    $targetState.monitors = @(
        foreach ($monitor in @($targetState.monitors)) {
            $deviceName = [string] $monitor.device_name
            $isRequested = $requestedDeviceNames.Contains($deviceName)
            $targetMonitor = ConvertTo-ParsecPlainObject -InputObject $monitor

            if ($isRequested) {
                $targetMonitor.enabled = $true
                $targetMonitor.is_primary = ($deviceName -eq [string] $primaryMonitor.device_name)
                if ($targetMonitor.Contains('bounds') -and $targetMonitor.bounds -is [System.Collections.IDictionary]) {
                    if ($null -ne $targetMonitor.bounds.x) {
                        $targetMonitor.bounds.x = [int] $targetMonitor.bounds.x - $primaryOffsetX
                    }
                    if ($null -ne $targetMonitor.bounds.y) {
                        $targetMonitor.bounds.y = [int] $targetMonitor.bounds.y - $primaryOffsetY
                    }
                }

                if ($targetMonitor.Contains('topology') -and $targetMonitor.topology -is [System.Collections.IDictionary]) {
                    $targetMonitor.topology.is_active = $true
                    if ($targetMonitor.topology.Contains('source_mode') -and $targetMonitor.topology.source_mode -is [System.Collections.IDictionary]) {
                        $targetMonitor.topology.source_mode.available = $true
                        if ($targetMonitor.topology.source_mode.Contains('position_x') -and $null -ne $targetMonitor.topology.source_mode.position_x) {
                            $targetMonitor.topology.source_mode.position_x = [int] $targetMonitor.topology.source_mode.position_x - $primaryOffsetX
                        }
                        if ($targetMonitor.topology.source_mode.Contains('position_y') -and $null -ne $targetMonitor.topology.source_mode.position_y) {
                            $targetMonitor.topology.source_mode.position_y = [int] $targetMonitor.topology.source_mode.position_y - $primaryOffsetY
                        }
                    }

                    if ($targetMonitor.topology.Contains('target_mode') -and $targetMonitor.topology.target_mode -is [System.Collections.IDictionary]) {
                        $targetMonitor.topology.target_mode.available = $true
                    }
                }
            }
            else {
                $targetMonitor.enabled = $false
                $targetMonitor.is_primary = $false
                $targetMonitor.orientation = $null
                $targetMonitor.bounds = [ordered]@{
                    x = $null
                    y = $null
                    width = $null
                    height = $null
                }
                if ($targetMonitor.Contains('display') -and $targetMonitor.display -is [System.Collections.IDictionary]) {
                    $targetMonitor.display.width = $null
                    $targetMonitor.display.height = $null
                }

                if ($targetMonitor.Contains('topology') -and $targetMonitor.topology -is [System.Collections.IDictionary]) {
                    $targetMonitor.topology.is_active = $false
                    if ($targetMonitor.topology.Contains('source_mode') -and $targetMonitor.topology.source_mode -is [System.Collections.IDictionary]) {
                        $targetMonitor.topology.source_mode.available = $false
                        $targetMonitor.topology.source_mode.width = $null
                        $targetMonitor.topology.source_mode.height = $null
                        $targetMonitor.topology.source_mode.position_x = $null
                        $targetMonitor.topology.source_mode.position_y = $null
                    }

                    if ($targetMonitor.topology.Contains('target_mode') -and $targetMonitor.topology.target_mode -is [System.Collections.IDictionary]) {
                        $targetMonitor.topology.target_mode.available = $false
                        $targetMonitor.topology.target_mode.width = $null
                        $targetMonitor.topology.target_mode.height = $null
                    }
                }
            }

            $targetMonitor
        }
    )

    return New-ParsecResult -Status 'Succeeded' -Message 'Resolved target active-display topology.' -Observed $ObservedState -Outputs @{
        target_state = $targetState
        requested_screen_ids = @($requestedScreenIds | ForEach-Object { [int] $_ })
        requested_device_names = @($requestedMonitors | ForEach-Object { [string] $_.device_name })
        primary_device_name = [string] $primaryMonitor.device_name
    }
}

function Resolve-ParsecActiveDisplayTargetStateForOperation {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    if ($null -ne $ExecutionResult -and $ExecutionResult.Outputs -and $ExecutionResult.Outputs.target_state) {
        return ConvertTo-ParsecPlainObject -InputObject $ExecutionResult.Outputs.target_state
    }

    $observed = Get-ParsecDisplayDomainObservedState
    $resolution = Resolve-ParsecActiveDisplayTargetState -ObservedState $observed -Arguments $Arguments -StateRoot $StateRoot
    if (-not (Test-ParsecSuccessfulStatus -Status $resolution.Status)) {
        return $resolution
    }

    return ConvertTo-ParsecPlainObject -InputObject $resolution.Outputs.target_state
}


function Initialize-ParsecDisplayAdapter {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if ($null -ne (Get-ParsecModuleVariableValue -Name 'ParsecDisplayAdapter')) {
        return
    }

    Set-ParsecModuleVariableValue -Name 'ParsecDisplayAdapter' -Value @{
        GetObservedState = {
            return Get-ParsecDisplayCaptureState
        }
        SetEnabled = {
            param([hashtable] $Arguments)
            return Set-ParsecDisplayEnabledInternal -Arguments $Arguments
        }
        SetPrimary = {
            param([hashtable] $Arguments)
            return Set-ParsecDisplayPrimaryInternal -Arguments $Arguments
        }
        SetResolution = {
            param([hashtable] $Arguments)
            return Set-ParsecDisplayResolutionInternal -Arguments $Arguments
        }
        SetOrientation = {
            param([hashtable] $Arguments)
            return Set-ParsecDisplayOrientationInternal -Arguments $Arguments
        }
        SetScaling = {
            param([hashtable] $Arguments)
            if ($Arguments.ContainsKey('text_scale_percent') -or ($Arguments.ContainsKey('value') -and -not $Arguments.ContainsKey('device_name'))) {
                if ($Arguments.ContainsKey('text_scale_percent')) {
                    return Invoke-ParsecPersonalizationAdapter -Method 'SetTextScale' -Arguments $Arguments
                }

                if ($Arguments.ContainsKey('ui_scale_percent') -or $Arguments.ContainsKey('scale_percent') -or ($Arguments.ContainsKey('value') -and -not $Arguments.ContainsKey('text_scale_percent'))) {
                    return Set-ParsecUiScaleStateInternal -Arguments $Arguments
                }

                return Invoke-ParsecPersonalizationAdapter -Method 'SetTextScale' -Arguments $Arguments
            }

            return New-ParsecResult -Status 'Failed' -Message 'Per-monitor UI scaling changes require a concrete backend implementation.' -Requested $Arguments -Errors @('CapabilityUnavailable')
        }
    } | Out-Null
}

function Invoke-ParsecDisplayAdapter {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Method,

        [Parameter()]
        [hashtable] $Arguments = @{}
    )

    Initialize-ParsecDisplayAdapter
    $adapter = Get-ParsecModuleVariableValue -Name 'ParsecDisplayAdapter'
    if ($null -eq $adapter -or -not $adapter.ContainsKey($Method)) {
        throw "Display adapter method '$Method' is not available."
    }

    return & $adapter[$Method] $Arguments
}

