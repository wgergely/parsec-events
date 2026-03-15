function Get-ParsecThemeState {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    $path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $appsUseLightTheme = 1
    $systemUsesLightTheme = 1

    try {
        $appsUseLightTheme = [int] (Get-ItemPropertyValue -Path $path -Name 'AppsUseLightTheme' -ErrorAction Stop)
    }
    catch {
        Write-Verbose 'AppsUseLightTheme could not be read from the registry. Falling back to Light.'
    }

    try {
        $systemUsesLightTheme = [int] (Get-ItemPropertyValue -Path $path -Name 'SystemUsesLightTheme' -ErrorAction Stop)
    }
    catch {
        Write-Verbose 'SystemUsesLightTheme could not be read from the registry. Falling back to Light.'
    }

    $appMode = if ($appsUseLightTheme -eq 0) { 'Dark' } else { 'Light' }
    $systemMode = if ($systemUsesLightTheme -eq 0) { 'Dark' } else { 'Light' }
    $mode = if ($appMode -eq $systemMode) { $appMode } else { 'Custom' }

    return [ordered]@{
        mode = $mode
        app_mode = $appMode
        system_mode = $systemMode
        apps_use_light_theme = $appsUseLightTheme
        system_uses_light_theme = $systemUsesLightTheme
    }
}

function Get-ParsecWallpaperState {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param()

    $desktopPath = 'HKCU:\Control Panel\Desktop'
    $colorsPath = 'HKCU:\Control Panel\Colors'
    $wallpaperPath = ''
    $wallpaperStyle = ''
    $tileWallpaper = ''
    $backgroundColor = ''

    try {
        $wallpaperPath = [ParsecEventExecutor.DisplayNative]::GetDesktopWallpaperPath()
    }
    catch {
        Write-Verbose 'Desktop wallpaper path could not be queried through SystemParametersInfo. Falling back to registry.'
    }

    if ([string]::IsNullOrWhiteSpace($wallpaperPath)) {
        try {
            $wallpaperPath = [string] (Get-ItemPropertyValue -Path $desktopPath -Name 'WallPaper' -ErrorAction Stop)
        }
        catch {
            $wallpaperPath = ''
        }
    }

    try {
        $wallpaperStyle = [string] (Get-ItemPropertyValue -Path $desktopPath -Name 'WallpaperStyle' -ErrorAction Stop)
    }
    catch {
        $wallpaperStyle = ''
    }

    try {
        $tileWallpaper = [string] (Get-ItemPropertyValue -Path $desktopPath -Name 'TileWallpaper' -ErrorAction Stop)
    }
    catch {
        $tileWallpaper = ''
    }

    try {
        $backgroundColor = [string] (Get-ItemPropertyValue -Path $colorsPath -Name 'Background' -ErrorAction Stop)
    }
    catch {
        $backgroundColor = ''
    }

    return [ordered]@{
        path = $wallpaperPath
        wallpaper_style = $wallpaperStyle
        tile_wallpaper = $tileWallpaper
        background_color = $backgroundColor
    }
}

function Initialize-ParsecPersonalizationInterop {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if ('ParsecEventExecutor.PersonalizationNative' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace ParsecEventExecutor {
    public static class PersonalizationNative {
        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        private static extern IntPtr SendMessageTimeout(
            IntPtr hWnd, uint msg, IntPtr wParam, string lParam,
            uint fuFlags, uint uTimeout, out IntPtr lpdwResult);

        public static void BroadcastSettingChange(string area) {
            IntPtr result;
            var timeoutFlags = 0x0002u | 0x0008u;
            var messageResult = SendMessageTimeout(
                new IntPtr(0xffff), 0x001A, IntPtr.Zero, area,
                timeoutFlags, 5000u, out result);
            if (messageResult == IntPtr.Zero) {
                throw new Win32Exception(
                    Marshal.GetLastWin32Error(),
                    "SendMessageTimeout(WM_SETTINGCHANGE) failed.");
            }
        }
    }
}
"@ -ErrorAction Stop
}

function Set-ParsecThemeStateInternal {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Arguments
    )

    $themeState = if ($Arguments.ContainsKey('theme_state') -and $Arguments.theme_state -is [System.Collections.IDictionary]) {
        ConvertTo-ParsecPlainObject -InputObject $Arguments.theme_state
    }
    else {
        $null
    }

    $mode = if ($Arguments.ContainsKey('mode')) { [string] $Arguments.mode } elseif ($null -ne $themeState -and $themeState.Contains('mode')) { [string] $themeState.mode } else { $null }
    $appMode = if ($Arguments.ContainsKey('app_mode')) { [string] $Arguments.app_mode } elseif ($null -ne $themeState -and $themeState.Contains('app_mode')) { [string] $themeState.app_mode } else { $null }
    $systemMode = if ($Arguments.ContainsKey('system_mode')) { [string] $Arguments.system_mode } elseif ($null -ne $themeState -and $themeState.Contains('system_mode')) { [string] $themeState.system_mode } else { $null }

    switch ($mode) {
        'Dark' {
            $appMode = 'Dark'
            $systemMode = 'Dark'
        }
        'Light' {
            $appMode = 'Light'
            $systemMode = 'Light'
        }
        'Custom' {
            if ([string]::IsNullOrWhiteSpace($appMode) -or [string]::IsNullOrWhiteSpace($systemMode)) {
                throw 'Custom theme mode requires both app_mode and system_mode.'
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($appMode) -or [string]::IsNullOrWhiteSpace($systemMode)) {
        throw 'Theme apply requires mode or both app_mode and system_mode.'
    }

    $appsUseLightTheme = if ($appMode -ieq 'Dark') { 0 } else { 1 }
    $systemUsesLightTheme = if ($systemMode -ieq 'Dark') { 0 } else { 1 }

    $path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    New-ItemProperty -Path $path -Name 'AppsUseLightTheme' -Value $appsUseLightTheme -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $path -Name 'SystemUsesLightTheme' -Value $systemUsesLightTheme -PropertyType DWord -Force | Out-Null
    Initialize-ParsecPersonalizationInterop
    [ParsecEventExecutor.PersonalizationNative]::BroadcastSettingChange('ImmersiveColorSet')
    [ParsecEventExecutor.PersonalizationNative]::BroadcastSettingChange('WindowsThemeElement')

    $state = Get-ParsecThemeState
    return New-ParsecResult -Status 'Succeeded' -Message ("Theme set to app={0}, system={1}." -f $state.app_mode, $state.system_mode) -Observed $state -Outputs @{
        theme_state = $state
    }
}

function Set-ParsecWallpaperStateInternal {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Arguments
    )

    $wallpaperState = if ($Arguments.ContainsKey('wallpaper_state') -and $Arguments.wallpaper_state -is [System.Collections.IDictionary]) {
        ConvertTo-ParsecPlainObject -InputObject $Arguments.wallpaper_state
    }
    else {
        $null
    }

    $wallpaperPath = if ($Arguments.ContainsKey('path')) {
        [string] $Arguments.path
    }
    elseif ($null -ne $wallpaperState -and $wallpaperState.Contains('path')) {
        [string] $wallpaperState.path
    }
    else {
        ''
    }

    $wallpaperStyle = if ($Arguments.ContainsKey('wallpaper_style')) {
        [string] $Arguments.wallpaper_style
    }
    elseif ($null -ne $wallpaperState -and $wallpaperState.Contains('wallpaper_style')) {
        [string] $wallpaperState.wallpaper_style
    }
    else {
        ''
    }

    $tileWallpaper = if ($Arguments.ContainsKey('tile_wallpaper')) {
        [string] $Arguments.tile_wallpaper
    }
    elseif ($null -ne $wallpaperState -and $wallpaperState.Contains('tile_wallpaper')) {
        [string] $wallpaperState.tile_wallpaper
    }
    else {
        ''
    }

    $backgroundColor = if ($Arguments.ContainsKey('background_color')) {
        [string] $Arguments.background_color
    }
    elseif ($null -ne $wallpaperState -and $wallpaperState.Contains('background_color')) {
        [string] $wallpaperState.background_color
    }
    else {
        ''
    }

    $desktopPath = 'HKCU:\Control Panel\Desktop'
    $colorsPath = 'HKCU:\Control Panel\Colors'
    if (-not (Test-Path -LiteralPath $desktopPath)) {
        New-Item -Path $desktopPath -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $colorsPath)) {
        New-Item -Path $colorsPath -Force | Out-Null
    }

    New-ItemProperty -Path $desktopPath -Name 'WallpaperStyle' -Value $wallpaperStyle -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $desktopPath -Name 'TileWallpaper' -Value $tileWallpaper -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $desktopPath -Name 'WallPaper' -Value $wallpaperPath -PropertyType String -Force | Out-Null
    if (-not [string]::IsNullOrWhiteSpace($backgroundColor)) {
        New-ItemProperty -Path $colorsPath -Name 'Background' -Value $backgroundColor -PropertyType String -Force | Out-Null
    }

    Initialize-ParsecPersonalizationInterop
    [ParsecEventExecutor.DisplayNative]::SetDesktopWallpaper($wallpaperPath)
    [ParsecEventExecutor.PersonalizationNative]::BroadcastSettingChange('Control Panel\Desktop')
    [ParsecEventExecutor.PersonalizationNative]::BroadcastSettingChange('Environment')

    $state = Get-ParsecWallpaperState
    return New-ParsecResult -Status 'Succeeded' -Message 'Wallpaper state restored.' -Observed $state -Outputs @{
        wallpaper_state = $state
    }
}

function Set-ParsecTextScaleStateInternal {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Arguments
    )

    $textScalePercent = if ($Arguments.ContainsKey('text_scale_percent')) {
        [int] $Arguments.text_scale_percent
    }
    elseif ($Arguments.ContainsKey('value')) {
        [int] $Arguments.value
    }
    elseif ($Arguments.ContainsKey('captured_state') -and $Arguments.captured_state -is [System.Collections.IDictionary] -and $Arguments.captured_state.Contains('text_scale_percent')) {
        [int] $Arguments.captured_state.text_scale_percent
    }
    else {
        throw 'Scaling apply requires text_scale_percent or value.'
    }

    if ($textScalePercent -lt 100 -or $textScalePercent -gt 225) {
        throw 'Text scaling percent must be between 100 and 225.'
    }

    $path = 'HKCU:\SOFTWARE\Microsoft\Accessibility'
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    # Windows bug workaround: text scale changes do not always trigger a UI re-render.
    # Double-apply with an intermediate value forces Windows to process the change.
    # When increasing: intermediate = n-1, then n (approach from below).
    # When decreasing: intermediate = n+1, then n (approach from above).
    # This always runs regardless of whether the current value matches the target.
    $currentValue = (Get-ItemProperty -Path $path -Name 'TextScaleFactor' -ErrorAction SilentlyContinue).TextScaleFactor
    $currentInt = if ($null -ne $currentValue) { [int] $currentValue } else { 100 }

    $intermediateValue = if ($textScalePercent -ge $currentInt) {
        $textScalePercent - 1
    }
    else {
        $textScalePercent + 1
    }
    $intermediateValue = [Math]::Max(100, [Math]::Min(225, $intermediateValue))

    Initialize-ParsecPersonalizationInterop
    New-ItemProperty -Path $path -Name 'TextScaleFactor' -Value $intermediateValue -PropertyType DWord -Force | Out-Null
    [ParsecEventExecutor.PersonalizationNative]::BroadcastSettingChange('Accessibility')
    [ParsecEventExecutor.PersonalizationNative]::BroadcastSettingChange('WindowMetrics')
    [ParsecEventExecutor.PersonalizationNative]::BroadcastSettingChange('Control Panel\Desktop')
    Start-Sleep -Milliseconds 500

    New-ItemProperty -Path $path -Name 'TextScaleFactor' -Value $textScalePercent -PropertyType DWord -Force | Out-Null
    [ParsecEventExecutor.PersonalizationNative]::BroadcastSettingChange('Accessibility')
    [ParsecEventExecutor.PersonalizationNative]::BroadcastSettingChange('WindowMetrics')
    [ParsecEventExecutor.PersonalizationNative]::BroadcastSettingChange('Control Panel\Desktop')

    return New-ParsecResult -Status 'Succeeded' -Message "Text scaling set to $textScalePercent%." -Observed @{
        text_scale_percent = $textScalePercent
    } -Outputs @{
        text_scale_percent = $textScalePercent
    }
}

function Set-ParsecUiScaleStateInternal {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Arguments
    )

    $scalePercent = if ($Arguments.ContainsKey('ui_scale_percent')) {
        [int] $Arguments.ui_scale_percent
    }
    elseif ($Arguments.ContainsKey('scale_percent')) {
        [int] $Arguments.scale_percent
    }
    elseif ($Arguments.ContainsKey('value')) {
        [int] $Arguments.value
    }
    elseif ($Arguments.ContainsKey('captured_state') -and $Arguments.captured_state -is [System.Collections.IDictionary] -and $Arguments.captured_state.Contains('ui_scale_percent')) {
        [int] $Arguments.captured_state.ui_scale_percent
    }
    else {
        throw 'UI scaling apply requires ui_scale_percent, scale_percent, or value.'
    }

    if ($scalePercent -lt 100 -or $scalePercent -gt 500) {
        throw 'UI scaling percent must be between 100 and 500.'
    }

    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments
    Initialize-ParsecDisplayInterop
    $appliedScalePercent = [int] [ParsecEventExecutor.DisplayNative]::SetDpiScaleForDevice($deviceName, [uint32] $scalePercent)

    return New-ParsecResult -Status 'Succeeded' -Message "UI scaling requested at $scalePercent%." -Observed @{
        device_name = $deviceName
        ui_scale_percent = $appliedScalePercent
        requires_signout = $false
    } -Outputs @{
        device_name = $deviceName
        ui_scale_percent = $appliedScalePercent
        requires_signout = $false
    }
}

function Initialize-ParsecPersonalizationAdapter {
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if ($null -ne (Get-ParsecModuleVariableValue -Name 'ParsecPersonalizationAdapter')) {
        return
    }

    Set-ParsecModuleVariableValue -Name 'ParsecPersonalizationAdapter' -Value @{
        GetThemeState = {
            return Get-ParsecThemeState
        }
        GetWallpaperState = {
            return Get-ParsecWallpaperState
        }
        SetThemeState = {
            param([hashtable] $Arguments)
            return Set-ParsecThemeStateInternal -Arguments $Arguments
        }
        SetWallpaperState = {
            param([hashtable] $Arguments)
            return Set-ParsecWallpaperStateInternal -Arguments $Arguments
        }
        SetUiScale = {
            param([hashtable] $Arguments)
            return Set-ParsecUiScaleStateInternal -Arguments $Arguments
        }
        SetTextScale = {
            param([hashtable] $Arguments)
            return Set-ParsecTextScaleStateInternal -Arguments $Arguments
        }
    } | Out-Null
}

function Invoke-ParsecPersonalizationAdapter {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string] $Method,

        [Parameter()]
        [hashtable] $Arguments = @{}
    )

    Initialize-ParsecPersonalizationAdapter
    $adapter = Get-ParsecModuleVariableValue -Name 'ParsecPersonalizationAdapter'
    if ($null -eq $adapter -or -not $adapter.ContainsKey($Method)) {
        throw "Personalization adapter method '$Method' is not available."
    }

    return & $adapter[$Method] $Arguments
}

