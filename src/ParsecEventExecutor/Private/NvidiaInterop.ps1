function Initialize-ParsecNvidiaInterop {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    # Type is loaded via RequiredAssemblies in ParsecEventExecutor.psd1
    if (-not ('ParsecEventExecutor.NvidiaApiNative' -as [type])) {
        throw 'ParsecEventExecutor.Native.dll is not loaded. Ensure the module is imported correctly.'
    }
}


function Get-ParsecNvidiaApiLibraryPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string] $PreferredPath
    )

    $candidates = New-Object System.Collections.Generic.List[string]
    if (-not [string]::IsNullOrWhiteSpace($PreferredPath)) {
        $candidates.Add($PreferredPath)
    }

    $systemRoot = [Environment]::GetFolderPath('System')
    if (-not [string]::IsNullOrWhiteSpace($systemRoot)) {
        $candidates.Add((Join-Path -Path $systemRoot -ChildPath 'nvapi64.dll'))
    }

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function ConvertTo-ParsecNvidiaDisplayName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $DeviceName
    )

    if ($DeviceName.StartsWith('\\.\')) {
        return $DeviceName
    }

    if ($DeviceName.StartsWith('\\')) {
        return ('\\.\' + $DeviceName.TrimStart('\'))
    }

    return ('\\.\' + $DeviceName.TrimStart('\'))
}

function Get-ParsecNvidiaBackendAvailability {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter()]
        [string] $LibraryPath
    )

    $resolvedLibraryPath = Get-ParsecNvidiaApiLibraryPath -PreferredPath $LibraryPath
    if ([string]::IsNullOrWhiteSpace($resolvedLibraryPath)) {
        return [ordered]@{
            available = $false
            library_path = $null
            backend = 'NvidiaApi'
            message = 'NVAPI library was not found.'
            errors = @('LibraryNotFound')
        }
    }

    try {
        Initialize-ParsecNvidiaInterop
        [ParsecEventExecutor.NvidiaApiNative]::EnsureInitialized($resolvedLibraryPath)
        return [ordered]@{
            available = $true
            library_path = $resolvedLibraryPath
            backend = 'NvidiaApi'
            message = 'NVAPI is available.'
            errors = @()
        }
    }
    catch {
        return [ordered]@{
            available = $false
            library_path = $resolvedLibraryPath
            backend = 'NvidiaApi'
            message = $_.Exception.Message
            errors = @('InitializationFailed')
        }
    }
}

function Get-ParsecNvidiaDisplayTargetInternal {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string] $DeviceName,

        [Parameter()]
        [string] $LibraryPath
    )

    $availability = Get-ParsecNvidiaBackendAvailability -LibraryPath $LibraryPath
    if (-not $availability.available) {
        throw $availability.message
    }

    $normalizedDisplayName = ConvertTo-ParsecNvidiaDisplayName -DeviceName $DeviceName
    $displayId = [ParsecEventExecutor.NvidiaApiNative]::GetDisplayIdByDisplayName($availability.library_path, $normalizedDisplayName)
    return [ordered]@{
        device_name = $DeviceName
        normalized_display_name = $normalizedDisplayName
        display_id = [uint32] $displayId
        library_path = $availability.library_path
        backend = $availability.backend
    }
}

function Get-ParsecNvidiaCustomResolutionInternal {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary[]])]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)]
        [uint32] $DisplayId,

        [Parameter()]
        [string] $LibraryPath
    )

    $availability = Get-ParsecNvidiaBackendAvailability -LibraryPath $LibraryPath
    if (-not $availability.available) {
        throw $availability.message
    }

    $customDisplays = @([ParsecEventExecutor.NvidiaApiNative]::EnumCustomDisplays($availability.library_path, $DisplayId))
    return @(
        foreach ($customDisplay in $customDisplays) {
            [ordered]@{
                width = [int] $customDisplay.Width
                height = [int] $customDisplay.Height
                depth = [int] $customDisplay.Depth
                color_format = [int] $customDisplay.ColorFormat
                refresh_rate_hz = [double] $customDisplay.RefreshRateHz
                timing_status = [uint32] $customDisplay.TimingStatus
                hardware_mode_set_only = [bool] $customDisplay.HardwareModeSetOnly
            }
        }
    )
}

function Add-ParsecNvidiaCustomResolutionInternal {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Arguments
    )

    $displayId = [uint32] $Arguments.display_id
    $width = [uint32] $Arguments.width
    $height = [uint32] $Arguments.height
    $refreshRateHz = [single] $Arguments.refresh_rate_hz
    $depth = if ($Arguments.ContainsKey('bits_per_pel')) { [uint32] $Arguments.bits_per_pel } else { [uint32] 32 }
    $libraryPath = if ($Arguments.ContainsKey('library_path')) { [string] $Arguments.library_path } else { $null }

    try {
        $availability = Get-ParsecNvidiaBackendAvailability -LibraryPath $libraryPath
        if (-not $availability.available) {
            return New-ParsecResult -Status 'Failed' -Message $availability.message -Requested $Arguments -Outputs @{
                display_id = [uint32] $displayId
                width = [int] $width
                height = [int] $height
                refresh_rate_hz = [double] $refreshRateHz
                bits_per_pel = [int] $depth
            } -Errors @('CapabilityUnavailable')
        }

        $customDisplay = [ParsecEventExecutor.NvidiaApiNative]::TryAndSaveCustomDisplay($availability.library_path, $displayId, $width, $height, $refreshRateHz, $depth)
        return New-ParsecResult -Status 'Succeeded' -Message ("Saved NVIDIA custom resolution {0}x{1}@{2:0.###}." -f $width, $height, $refreshRateHz) -Requested $Arguments -Outputs @{
            display_id = [uint32] $displayId
            width = [int] $customDisplay.Width
            height = [int] $customDisplay.Height
            refresh_rate_hz = [double] $customDisplay.RefreshRateHz
            bits_per_pel = [int] $customDisplay.Depth
            color_format = [int] $customDisplay.ColorFormat
            timing_status = [uint32] $customDisplay.TimingStatus
            hardware_mode_set_only = [bool] $customDisplay.HardwareModeSetOnly
            library_path = $availability.library_path
        }
    }
    catch {
        return New-ParsecResult -Status 'Failed' -Message $_.Exception.Message -Requested $Arguments -Outputs @{
            display_id = [uint32] $displayId
            width = [int] $width
            height = [int] $height
            refresh_rate_hz = [double] $refreshRateHz
            bits_per_pel = [int] $depth
        } -Errors @('NvidiaApiError')
    }
}
