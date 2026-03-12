function New-ParsecIngredientDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Kind,

        [Parameter(Mandatory)]
        [hashtable] $Operations,

        [Parameter()]
        [string] $Description = '',

        [Parameter()]
        [string[]] $Capabilities = @(),

        [Parameter()]
        [string[]] $Aliases = @(),

        [Parameter()]
        [string[]] $RequiredBackends = @(),

        [Parameter()]
        [hashtable] $OperationSchemas = @{},

        [Parameter()]
        [string] $SafetyClass = 'ReadOnly',

        [Parameter()]
        [string[]] $SuccessSignals = @(),

        [Parameter()]
        [string[]] $FailureSignals = @(),

        [Parameter()]
        [string[]] $WaitConditions = @(),

        [Parameter()]
        [hashtable] $Readiness = @{}
    )

    return [pscustomobject]@{
        PSTypeName = 'ParsecEventExecutor.IngredientDefinition'
        Name = $Name
        Aliases = @($Aliases)
        Kind = $Kind
        Description = $Description
        Capabilities = @($Capabilities)
        RequiredBackends = @($RequiredBackends)
        OperationSchemas = $OperationSchemas
        Operations = $Operations
        SafetyClass = $SafetyClass
        SuccessSignals = @($SuccessSignals)
        FailureSignals = @($FailureSignals)
        WaitConditions = @($WaitConditions)
        Readiness = ConvertTo-ParsecPlainObject -InputObject $Readiness
    }
}

function Register-ParsecIngredient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Definition
    )

    $script:ParsecIngredientRegistry[$Definition.Name] = $Definition
    foreach ($alias in @($Definition.Aliases)) {
        if ([string]::IsNullOrWhiteSpace([string] $alias)) {
            continue
        }

        $script:ParsecIngredientAliasRegistry[[string] $alias] = $Definition.Name
    }

    return $Definition
}

function Resolve-ParsecIngredientName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    if ($script:ParsecIngredientRegistry.ContainsKey($Name)) {
        return $Name
    }

    if ($script:ParsecIngredientAliasRegistry.ContainsKey($Name)) {
        return [string] $script:ParsecIngredientAliasRegistry[$Name]
    }

    throw "Ingredient '$Name' is not registered."
}

function Get-ParsecIngredientDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $resolvedName = Resolve-ParsecIngredientName -Name $Name
    return $script:ParsecIngredientRegistry[$resolvedName]
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
        'integer' {
            return (
                $Value -is [int16] -or
                $Value -is [int32] -or
                $Value -is [int64] -or
                $Value -is [uint16] -or
                $Value -is [uint32] -or
                $Value -is [uint64]
            )
        }
        'array' { return $Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] }
        'hashtable' { return $Value -is [System.Collections.IDictionary] }
        default { return $true }
    }
}

function Get-ParsecIngredientSchemaForOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Definition,

        [Parameter(Mandatory)]
        [string] $Operation
    )

    if (-not $Definition.OperationSchemas) {
        return @{}
    }

    if ($Definition.OperationSchemas.Contains($Operation)) {
        return $Definition.OperationSchemas[$Operation]
    }

    return @{}
}

function Assert-ParsecIngredientArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Definition,

        [Parameter(Mandatory)]
        [string] $Operation,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Arguments
    )

    $schema = Get-ParsecIngredientSchemaForOperation -Definition $Definition -Operation $Operation
    if (-not $schema -or $schema.Count -eq 0) {
        return
    }

    if ($schema.Contains('required')) {
        foreach ($required in @($schema.required)) {
            if ([string]::IsNullOrWhiteSpace([string] $required)) {
                continue
            }

            if (-not $Arguments.Contains($required)) {
                throw "Ingredient '$($Definition.Name)' operation '$Operation' requires argument '$required'."
            }
        }
    }

    if ($schema.Contains('types')) {
        foreach ($key in $schema.types.Keys) {
            if ($Arguments.Contains($key) -and -not (Test-ParsecArgumentType -Value $Arguments[$key] -TypeName $schema.types[$key])) {
                throw "Ingredient '$($Definition.Name)' operation '$Operation' argument '$key' must be of type '$($schema.types[$key])'."
            }
        }
    }
}

function Initialize-ParsecDisplayInterop {
    [CmdletBinding()]
    param()

    if ('ParsecEventExecutor.DisplayNative' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace ParsecEventExecutor {
    public sealed class MonitorCapture {
        public string DeviceName { get; set; }
        public bool IsPrimary { get; set; }
        public int Left { get; set; }
        public int Top { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
        public int WorkLeft { get; set; }
        public int WorkTop { get; set; }
        public int WorkWidth { get; set; }
        public int WorkHeight { get; set; }
        public int Orientation { get; set; }
        public int BitsPerPel { get; set; }
        public int DisplayFrequency { get; set; }
        public uint EffectiveDpiX { get; set; }
        public uint EffectiveDpiY { get; set; }
        public bool HasEffectiveDpi { get; set; }
    }

    public sealed class DisplayPathCapture {
        public string AdapterKey { get; set; }
        public uint SourceId { get; set; }
        public uint TargetId { get; set; }
        public string SourceDeviceName { get; set; }
        public string MonitorFriendlyName { get; set; }
        public string MonitorDevicePath { get; set; }
        public string AdapterDevicePath { get; set; }
        public bool IsActive { get; set; }
        public bool TargetAvailable { get; set; }
        public uint PathFlags { get; set; }
        public uint SourceStatusFlags { get; set; }
        public uint TargetStatusFlags { get; set; }
        public int Rotation { get; set; }
        public int Scaling { get; set; }
        public int OutputTechnology { get; set; }
        public int ScanLineOrdering { get; set; }
        public uint RefreshRateNumerator { get; set; }
        public uint RefreshRateDenominator { get; set; }
        public bool HasSourceMode { get; set; }
        public uint SourceWidth { get; set; }
        public uint SourceHeight { get; set; }
        public int SourcePositionX { get; set; }
        public int SourcePositionY { get; set; }
        public int PixelFormat { get; set; }
        public bool HasTargetMode { get; set; }
        public uint TargetWidth { get; set; }
        public uint TargetHeight { get; set; }
        public ulong PixelRate { get; set; }
    }

    public sealed class DisplayModeCapture {
        public int Width { get; set; }
        public int Height { get; set; }
        public int BitsPerPel { get; set; }
        public int DisplayFrequency { get; set; }
        public int Orientation { get; set; }
    }

    public sealed class WindowCapture {
        public long Handle { get; set; }
        public long OwnerHandle { get; set; }
        public uint ProcessId { get; set; }
        public string ProcessName { get; set; }
        public string Title { get; set; }
        public string ClassName { get; set; }
        public bool IsVisible { get; set; }
        public bool IsMinimized { get; set; }
        public bool IsCloaked { get; set; }
        public bool IsShellWindow { get; set; }
        public long ExtendedStyle { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
    }

    public static class DisplayNative {
        private const int ENUM_CURRENT_SETTINGS = -1;
        private const int ENUM_REGISTRY_SETTINGS = -2;
        private const int MDT_EFFECTIVE_DPI = 0;
        private const int CCHDEVICENAME = 32;
        private const int CCHFORMNAME = 32;
        private const uint QDC_ALL_PATHS = 0x00000001;
        private const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
        private const uint QDC_VIRTUAL_MODE_AWARE = 0x00000010;
        private const uint QDC_VIRTUAL_REFRESH_RATE_AWARE = 0x00000040;
        private const uint DISPLAYCONFIG_PATH_ACTIVE = 0x00000001;
        private const uint DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE = 1;
        private const uint DISPLAYCONFIG_MODE_INFO_TYPE_TARGET = 2;
        private const uint DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME = 1;
        private const uint DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME = 2;
        private const uint DISPLAYCONFIG_DEVICE_INFO_GET_ADAPTER_NAME = 4;
        private static readonly uint DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE = unchecked((uint)-3);
        private static readonly uint DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE = unchecked((uint)-4);
        private const uint DISPLAYCONFIG_PATH_MODE_IDX_INVALID = 0xffffffff;
        public const int DM_POSITION = 0x00000020;
        public const int DM_DISPLAYORIENTATION = 0x00000080;
        public const int DM_BITSPERPEL = 0x00040000;
        public const int DM_PELSWIDTH = 0x00080000;
        public const int DM_PELSHEIGHT = 0x00100000;
        public const int DM_DISPLAYFREQUENCY = 0x00400000;
        public const int DM_DISPLAYFLAGS = 0x00200000;
        public const int CDS_UPDATEREGISTRY = 0x00000001;
        public const int CDS_TEST = 0x00000002;
        public const int CDS_SET_PRIMARY = 0x00000010;
        public const int CDS_NORESET = 0x10000000;
        public const int CDS_RESET = 0x40000000;
        public const int DISP_CHANGE_SUCCESSFUL = 0;
        public const int DISP_CHANGE_RESTART = 1;
        public const int DISP_CHANGE_FAILED = -1;
        public const int DISP_CHANGE_BADMODE = -2;
        public const int DISP_CHANGE_NOTUPDATED = -3;
        public const int DISP_CHANGE_BADFLAGS = -4;
        public const int DISP_CHANGE_BADPARAM = -5;
        public const int DISP_CHANGE_BADDUALVIEW = -6;
        public const int DMDO_DEFAULT = 0;
        public const int DMDO_90 = 1;
        public const int DMDO_180 = 2;
        public const int DMDO_270 = 3;
        public const int SPI_SETDESKWALLPAPER = 0x0014;
        public const int SPI_GETDESKWALLPAPER = 0x0073;
        public const int SPIF_UPDATEINIFILE = 0x0001;
        public const int SPIF_SENDCHANGE = 0x0002;
        private static readonly uint[] DpiScaleValues = new uint[] { 100, 125, 150, 175, 200, 225, 250, 300, 350, 400, 450, 500 };

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct GUITHREADINFO {
            public uint cbSize;
            public uint flags;
            public IntPtr hwndActive;
            public IntPtr hwndFocus;
            public IntPtr hwndCapture;
            public IntPtr hwndMenuOwner;
            public IntPtr hwndMoveSize;
            public IntPtr hwndCaret;
            public RECT rcCaret;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        public struct MONITORINFOEX {
            public int cbSize;
            public RECT rcMonitor;
            public RECT rcWork;
            public uint dwFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCHDEVICENAME)]
            public string szDevice;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        public struct DEVMODE {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCHDEVICENAME)]
            public string dmDeviceName;
            public short dmSpecVersion;
            public short dmDriverVersion;
            public short dmSize;
            public short dmDriverExtra;
            public int dmFields;
            public int dmPositionX;
            public int dmPositionY;
            public int dmDisplayOrientation;
            public int dmDisplayFixedOutput;
            public short dmColor;
            public short dmDuplex;
            public short dmYResolution;
            public short dmTTOption;
            public short dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = CCHFORMNAME)]
            public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel;
            public int dmPelsWidth;
            public int dmPelsHeight;
            public int dmDisplayFlags;
            public int dmDisplayFrequency;
            public int dmICMMethod;
            public int dmICMIntent;
            public int dmMediaType;
            public int dmDitherType;
            public int dmReserved1;
            public int dmReserved2;
            public int dmPanningWidth;
            public int dmPanningHeight;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct LUID {
            public uint LowPart;
            public int HighPart;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct POINTL {
            public int x;
            public int y;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_RATIONAL {
            public uint Numerator;
            public uint Denominator;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_2DREGION {
            public uint cx;
            public uint cy;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_PATH_SOURCE_INFO {
            public LUID adapterId;
            public uint id;
            public uint modeInfoIdx;
            public uint statusFlags;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_PATH_TARGET_INFO {
            public LUID adapterId;
            public uint id;
            public uint modeInfoIdx;
            public int outputTechnology;
            public int rotation;
            public int scaling;
            public DISPLAYCONFIG_RATIONAL refreshRate;
            public int scanLineOrdering;
            [MarshalAs(UnmanagedType.Bool)]
            public bool targetAvailable;
            public uint statusFlags;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_PATH_INFO {
            public DISPLAYCONFIG_PATH_SOURCE_INFO sourceInfo;
            public DISPLAYCONFIG_PATH_TARGET_INFO targetInfo;
            public uint flags;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_SOURCE_MODE {
            public uint width;
            public uint height;
            public uint pixelFormat;
            public POINTL position;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_VIDEO_SIGNAL_INFO {
            public ulong pixelRate;
            public DISPLAYCONFIG_RATIONAL hSyncFreq;
            public DISPLAYCONFIG_RATIONAL vSyncFreq;
            public DISPLAYCONFIG_2DREGION activeSize;
            public DISPLAYCONFIG_2DREGION totalSize;
            public uint videoStandard;
            public int scanLineOrdering;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_TARGET_MODE {
            public DISPLAYCONFIG_VIDEO_SIGNAL_INFO targetVideoSignalInfo;
        }

        [StructLayout(LayoutKind.Explicit)]
        public struct DISPLAYCONFIG_MODE_INFO_UNION {
            [FieldOffset(0)]
            public DISPLAYCONFIG_TARGET_MODE targetMode;

            [FieldOffset(0)]
            public DISPLAYCONFIG_SOURCE_MODE sourceMode;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_MODE_INFO {
            public uint infoType;
            public uint id;
            public LUID adapterId;
            public DISPLAYCONFIG_MODE_INFO_UNION modeInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_DEVICE_INFO_HEADER {
            public uint type;
            public uint size;
            public LUID adapterId;
            public uint id;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_SOURCE_DPI_SCALE_GET {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            public int minScaleRel;
            public int curScaleRel;
            public int maxScaleRel;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct DISPLAYCONFIG_SOURCE_DPI_SCALE_SET {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            public int scaleRel;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DISPLAYCONFIG_SOURCE_DEVICE_NAME {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
            public string viewGdiDeviceName;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DISPLAYCONFIG_TARGET_DEVICE_NAME {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            public uint flags;
            public int outputTechnology;
            public ushort edidManufactureId;
            public ushort edidProductCodeId;
            public uint connectorInstance;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
            public string monitorFriendlyDeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string monitorDevicePath;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct DISPLAYCONFIG_ADAPTER_NAME {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            public string adapterDevicePath;
        }

        private delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData);
        private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);

        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool EnumDisplaySettings(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool EnumDisplaySettingsEx(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode, uint dwFlags);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern int ChangeDisplaySettingsEx(string lpszDeviceName, IntPtr lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

        [DllImport("Shcore.dll")]
        private static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern IntPtr GetShellWindow();

        [StructLayout(LayoutKind.Sequential)]
        private struct INPUT {
            public uint type;
            public INPUTUNION U;
        }

        [StructLayout(LayoutKind.Explicit)]
        private struct INPUTUNION {
            [FieldOffset(0)]
            public KEYBDINPUT ki;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct KEYBDINPUT {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public uint time;
            public IntPtr dwExtraInfo;
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

        [DllImport("user32.dll")]
        private static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool BringWindowToTop(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool IsWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern bool IsIconic(IntPtr hWnd);

        [DllImport("user32.dll")]
        private static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowTextLengthW(IntPtr hWnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowTextW(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassNameW(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool GetGUIThreadInfo(uint idThread, ref GUITHREADINFO lpgui);

        [DllImport("user32.dll")]
        private static extern IntPtr GetAncestor(IntPtr hWnd, uint gaFlags);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW", SetLastError = true)]
        private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", EntryPoint = "GetWindowLongW", SetLastError = true)]
        private static extern IntPtr GetWindowLongPtr32(IntPtr hWnd, int nIndex);

        [DllImport("dwmapi.dll", PreserveSig = true)]
        private static extern int DwmGetWindowAttribute(IntPtr hWnd, uint dwAttribute, out int pvAttribute, int cbAttribute);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool SystemParametersInfo(uint uiAction, uint uiParam, StringBuilder pvParam, uint fWinIni);

        [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);

        [DllImport("user32.dll")]
        private static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPathArrayElements, out uint numModeInfoArrayElements);

        [DllImport("user32.dll")]
        private static extern int QueryDisplayConfig(uint flags, ref uint numPathArrayElements, [Out] DISPLAYCONFIG_PATH_INFO[] pathInfoArray, ref uint modeInfoArrayElements, [Out] DISPLAYCONFIG_MODE_INFO[] modeInfoArray, IntPtr currentTopologyId);

        [DllImport("user32.dll")]
        private static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_SOURCE_DEVICE_NAME requestPacket);

        [DllImport("user32.dll")]
        private static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_TARGET_DEVICE_NAME requestPacket);

        [DllImport("user32.dll")]
        private static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_ADAPTER_NAME requestPacket);

        [DllImport("user32.dll")]
        private static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_SOURCE_DPI_SCALE_GET requestPacket);

        [DllImport("user32.dll")]
        private static extern int DisplayConfigSetDeviceInfo(ref DISPLAYCONFIG_SOURCE_DPI_SCALE_SET setPacket);

        private static string AdapterIdToString(LUID value) {
            return value.HighPart.ToString("X8") + ":" + value.LowPart.ToString("X8");
        }

        private static IntPtr NormalizeTopLevelWindow(IntPtr hWnd) {
            if (hWnd == IntPtr.Zero) {
                return IntPtr.Zero;
            }

            var rootOwner = GetAncestor(hWnd, 3u);
            return rootOwner != IntPtr.Zero ? rootOwner : hWnd;
        }

        private static IntPtr ResolveForegroundWindowHandle() {
            var foregroundWindow = GetForegroundWindow();
            if (foregroundWindow != IntPtr.Zero) {
                return NormalizeTopLevelWindow(foregroundWindow);
            }

            var guiThreadInfo = new GUITHREADINFO();
            guiThreadInfo.cbSize = (uint)Marshal.SizeOf(typeof(GUITHREADINFO));
            if (!GetGUIThreadInfo(0u, ref guiThreadInfo)) {
                return IntPtr.Zero;
            }

            if (guiThreadInfo.hwndFocus != IntPtr.Zero) {
                return NormalizeTopLevelWindow(guiThreadInfo.hwndFocus);
            }

            if (guiThreadInfo.hwndActive != IntPtr.Zero) {
                return NormalizeTopLevelWindow(guiThreadInfo.hwndActive);
            }

            if (guiThreadInfo.hwndCaret != IntPtr.Zero) {
                return NormalizeTopLevelWindow(guiThreadInfo.hwndCaret);
            }

            return IntPtr.Zero;
        }

        private static IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex) {
            return IntPtr.Size == 8 ? GetWindowLongPtr64(hWnd, nIndex) : GetWindowLongPtr32(hWnd, nIndex);
        }

        private static bool TryGetWindowTitle(IntPtr hWnd, out string title) {
            title = string.Empty;
            var length = GetWindowTextLengthW(hWnd);
            if (length <= 0) {
                return false;
            }

            var builder = new StringBuilder(length + 1);
            if (GetWindowTextW(hWnd, builder, builder.Capacity) <= 0) {
                return false;
            }

            title = builder.ToString();
            return true;
        }

        private static string GetWindowClassName(IntPtr hWnd) {
            var builder = new StringBuilder(256);
            return GetClassNameW(hWnd, builder, builder.Capacity) > 0 ? builder.ToString() : string.Empty;
        }

        private static string TryGetProcessName(uint processId) {
            if (processId == 0) {
                return string.Empty;
            }

            try {
                var process = System.Diagnostics.Process.GetProcessById((int)processId);
                return process.ProcessName ?? string.Empty;
            }
            catch {
                return string.Empty;
            }
        }

        private static bool TryGetIsCloaked(IntPtr hWnd, out bool cloaked) {
            cloaked = false;
            try {
                int value = 0;
                if (DwmGetWindowAttribute(hWnd, 14u, out value, Marshal.SizeOf(typeof(int))) == 0) {
                    cloaked = value != 0;
                    return true;
                }
            }
            catch {
            }

            return false;
        }

        private static WindowCapture CaptureWindow(IntPtr hWnd) {
            if (hWnd == IntPtr.Zero || !IsWindow(hWnd)) {
                return null;
            }

            string title;
            TryGetWindowTitle(hWnd, out title);
            uint processId;
            GetWindowThreadProcessId(hWnd, out processId);
            RECT windowRect;
            GetWindowRect(hWnd, out windowRect);
            bool isCloaked;
            TryGetIsCloaked(hWnd, out isCloaked);
            var shellWindow = GetShellWindow();

            return new WindowCapture {
                Handle = hWnd.ToInt64(),
                OwnerHandle = GetWindow(hWnd, 4u).ToInt64(),
                ProcessId = processId,
                ProcessName = TryGetProcessName(processId),
                Title = title ?? string.Empty,
                ClassName = GetWindowClassName(hWnd),
                IsVisible = IsWindowVisible(hWnd),
                IsMinimized = IsIconic(hWnd),
                IsCloaked = isCloaked,
                IsShellWindow = shellWindow != IntPtr.Zero && hWnd == shellWindow,
                ExtendedStyle = GetWindowLongPtr(hWnd, -20).ToInt64(),
                Width = Math.Max(windowRect.Right - windowRect.Left, 0),
                Height = Math.Max(windowRect.Bottom - windowRect.Top, 0)
            };
        }

        private static DISPLAYCONFIG_MODE_INFO? FindModeInfo(DISPLAYCONFIG_MODE_INFO[] modes, LUID adapterId, uint id, uint infoType, uint modeInfoIdx) {
            if (modes == null || modeInfoIdx == DISPLAYCONFIG_PATH_MODE_IDX_INVALID) {
                return null;
            }

            if (modeInfoIdx < modes.Length) {
                var indexed = modes[modeInfoIdx];
                if (indexed.infoType == infoType && indexed.id == id && indexed.adapterId.LowPart == adapterId.LowPart && indexed.adapterId.HighPart == adapterId.HighPart) {
                    return indexed;
                }
            }

            for (var i = 0; i < modes.Length; i++) {
                var candidate = modes[i];
                if (candidate.infoType == infoType && candidate.id == id && candidate.adapterId.LowPart == adapterId.LowPart && candidate.adapterId.HighPart == adapterId.HighPart) {
                    return candidate;
                }
            }

            return null;
        }

        private static string TryGetSourceName(LUID adapterId, uint id) {
            var request = new DISPLAYCONFIG_SOURCE_DEVICE_NAME();
            request.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DEVICE_NAME));
            request.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
            request.header.adapterId = adapterId;
            request.header.id = id;
            return DisplayConfigGetDeviceInfo(ref request) == 0 ? request.viewGdiDeviceName : null;
        }

        private static DISPLAYCONFIG_TARGET_DEVICE_NAME? TryGetTargetName(LUID adapterId, uint id) {
            var request = new DISPLAYCONFIG_TARGET_DEVICE_NAME();
            request.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_TARGET_DEVICE_NAME));
            request.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
            request.header.adapterId = adapterId;
            request.header.id = id;
            return DisplayConfigGetDeviceInfo(ref request) == 0 ? request : (DISPLAYCONFIG_TARGET_DEVICE_NAME?)null;
        }

        private static string TryGetAdapterPath(LUID adapterId) {
            var request = new DISPLAYCONFIG_ADAPTER_NAME();
            request.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_ADAPTER_NAME));
            request.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_ADAPTER_NAME;
            request.header.adapterId = adapterId;
            request.header.id = 0;
            return DisplayConfigGetDeviceInfo(ref request) == 0 ? request.adapterDevicePath : null;
        }

        private static DISPLAYCONFIG_PATH_INFO[] QueryDisplayPaths(uint flags) {
            uint pathCount = 0;
            uint modeCount = 0;
            ThrowIfWin32Error(GetDisplayConfigBufferSizes(flags, out pathCount, out modeCount), "GetDisplayConfigBufferSizes");

            DISPLAYCONFIG_PATH_INFO[] paths = null;
            DISPLAYCONFIG_MODE_INFO[] modes = null;
            int queryError = 0;
            for (var attempt = 0; attempt < 3; attempt++) {
                paths = new DISPLAYCONFIG_PATH_INFO[pathCount];
                modes = new DISPLAYCONFIG_MODE_INFO[modeCount];
                queryError = QueryDisplayConfig(flags, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero);
                if (queryError == 0) {
                    if (paths.Length != pathCount) {
                        Array.Resize(ref paths, (int)pathCount);
                    }

                    return paths;
                }

                if (queryError != 122) {
                    ThrowIfWin32Error(queryError, "QueryDisplayConfig");
                }

                ThrowIfWin32Error(GetDisplayConfigBufferSizes(flags, out pathCount, out modeCount), "GetDisplayConfigBufferSizes");
            }

            ThrowIfWin32Error(queryError, "QueryDisplayConfig");
            return Array.Empty<DISPLAYCONFIG_PATH_INFO>();
        }

        private static bool TryResolveActiveSource(string deviceName, out LUID adapterId, out uint sourceId, out bool isPrimary) {
            adapterId = new LUID();
            sourceId = 0;
            isPrimary = false;

            var activePaths = QueryDisplayPaths(QDC_ONLY_ACTIVE_PATHS);
            var monitors = GetCurrentMonitors();
            foreach (var path in activePaths) {
                var sourceName = TryGetSourceName(path.sourceInfo.adapterId, path.sourceInfo.id);
                if (!string.Equals(sourceName, deviceName, StringComparison.OrdinalIgnoreCase)) {
                    continue;
                }

                adapterId = path.sourceInfo.adapterId;
                sourceId = path.sourceInfo.id;

                foreach (var monitor in monitors) {
                    if (string.Equals(monitor.DeviceName, deviceName, StringComparison.OrdinalIgnoreCase)) {
                        isPrimary = monitor.IsPrimary;
                        break;
                    }
                }

                return true;
            }

            return false;
        }

        private static bool TryGetDpiScalingInfo(LUID adapterId, uint sourceId, out uint current, out uint recommended, out uint minimum, out uint maximum) {
            current = 100;
            recommended = 100;
            minimum = 100;
            maximum = 100;

            var requestPacket = new DISPLAYCONFIG_SOURCE_DPI_SCALE_GET();
            requestPacket.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_DPI_SCALE;
            requestPacket.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DPI_SCALE_GET));
            requestPacket.header.adapterId = adapterId;
            requestPacket.header.id = sourceId;

            if (DisplayConfigGetDeviceInfo(ref requestPacket) != 0) {
                return false;
            }

            var curRel = requestPacket.curScaleRel;
            if (curRel < requestPacket.minScaleRel) {
                curRel = requestPacket.minScaleRel;
            }
            else if (curRel > requestPacket.maxScaleRel) {
                curRel = requestPacket.maxScaleRel;
            }

            var minAbs = Math.Abs(requestPacket.minScaleRel);
            var currentIndex = minAbs + curRel;
            var maximumIndex = minAbs + requestPacket.maxScaleRel;
            if (minAbs < 0 || minAbs >= DpiScaleValues.Length || currentIndex < 0 || currentIndex >= DpiScaleValues.Length || maximumIndex < 0 || maximumIndex >= DpiScaleValues.Length) {
                return false;
            }

            current = DpiScaleValues[currentIndex];
            recommended = DpiScaleValues[minAbs];
            minimum = DpiScaleValues[0];
            maximum = DpiScaleValues[maximumIndex];
            return true;
        }

        private static void SetAppliedDpi(uint dpiPercent) {
            using (var key = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(@"Control Panel\Desktop\WindowMetrics")) {
                if (key != null) {
                    key.SetValue("AppliedDPI", (int)Math.Round(dpiPercent * 0.96), Microsoft.Win32.RegistryValueKind.DWord);
                }
            }
        }

        private static void ThrowIfWin32Error(int errorCode, string apiName) {
            if (errorCode != 0) {
                throw new Win32Exception(errorCode, apiName + " failed.");
            }
        }

        public static void BroadcastSettingChange(string area) {
            IntPtr result;
            var timeoutFlags = 0x0002u | 0x0008u;
            var messageResult = SendMessageTimeout(new IntPtr(0xffff), 0x001A, IntPtr.Zero, area, timeoutFlags, 5000u, out result);
            if (messageResult == IntPtr.Zero) {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "SendMessageTimeout(WM_SETTINGCHANGE) failed.");
            }
        }

        public static WindowCapture GetForegroundWindowCapture() {
            return CaptureWindow(ResolveForegroundWindowHandle());
        }

        public static WindowCapture[] GetTopLevelWindows() {
            var windows = new List<WindowCapture>();
            EnumWindows(delegate (IntPtr hWnd, IntPtr lParam) {
                var capture = CaptureWindow(hWnd);
                if (capture != null) {
                    windows.Add(capture);
                }

                return true;
            }, IntPtr.Zero);

            return windows.ToArray();
        }

        public static bool StepAltTab() {
            var inputs = new INPUT[] {
                new INPUT { type = 1u, U = new INPUTUNION { ki = new KEYBDINPUT { wVk = 0x12 } } },
                new INPUT { type = 1u, U = new INPUTUNION { ki = new KEYBDINPUT { wVk = 0x09 } } },
                new INPUT { type = 1u, U = new INPUTUNION { ki = new KEYBDINPUT { wVk = 0x09, dwFlags = 0x0002u } } },
                new INPUT { type = 1u, U = new INPUTUNION { ki = new KEYBDINPUT { wVk = 0x12, dwFlags = 0x0002u } } }
            };

            return SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT))) == inputs.Length;
        }

        public static bool ActivateWindow(long handle, bool restoreIfMinimized) {
            var hWnd = new IntPtr(handle);
            if (!IsWindow(hWnd)) {
                return false;
            }

            return SetForegroundWindow(hWnd);
        }

        public static string GetDesktopWallpaperPath() {
            var buffer = new StringBuilder(260);
            if (!SystemParametersInfo(SPI_GETDESKWALLPAPER, (uint)buffer.Capacity, buffer, 0)) {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "SystemParametersInfo(SPI_GETDESKWALLPAPER) failed.");
            }

            return buffer.ToString();
        }

        public static void SetDesktopWallpaper(string path) {
            if (!SystemParametersInfo(SPI_SETDESKWALLPAPER, 0, path ?? string.Empty, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE)) {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "SystemParametersInfo(SPI_SETDESKWALLPAPER) failed.");
            }
        }

        public static DisplayPathCapture[] GetDisplayConfigPaths() {
            var flags = QDC_ALL_PATHS | QDC_VIRTUAL_MODE_AWARE | QDC_VIRTUAL_REFRESH_RATE_AWARE;
            uint pathCount = 0;
            uint modeCount = 0;
            var sizeError = GetDisplayConfigBufferSizes(flags, out pathCount, out modeCount);
            if (sizeError != 0) {
                flags = QDC_ALL_PATHS;
                ThrowIfWin32Error(GetDisplayConfigBufferSizes(flags, out pathCount, out modeCount), "GetDisplayConfigBufferSizes");
            }

            DISPLAYCONFIG_PATH_INFO[] paths = null;
            DISPLAYCONFIG_MODE_INFO[] modes = null;
            int queryError = 0;
            for (var attempt = 0; attempt < 3; attempt++) {
                paths = new DISPLAYCONFIG_PATH_INFO[pathCount];
                modes = new DISPLAYCONFIG_MODE_INFO[modeCount];
                queryError = QueryDisplayConfig(flags, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero);
                if (queryError == 0) {
                    break;
                }

                if (queryError != 122) {
                    if (flags != QDC_ALL_PATHS) {
                        flags = QDC_ALL_PATHS;
                        ThrowIfWin32Error(GetDisplayConfigBufferSizes(flags, out pathCount, out modeCount), "GetDisplayConfigBufferSizes");
                        continue;
                    }

                    ThrowIfWin32Error(queryError, "QueryDisplayConfig");
                }

                ThrowIfWin32Error(GetDisplayConfigBufferSizes(flags, out pathCount, out modeCount), "GetDisplayConfigBufferSizes");
            }

            ThrowIfWin32Error(queryError, "QueryDisplayConfig");

            var captures = new List<DisplayPathCapture>();
            for (var i = 0; i < pathCount; i++) {
                var path = paths[i];
                var sourceMode = FindModeInfo(modes, path.sourceInfo.adapterId, path.sourceInfo.id, DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE, path.sourceInfo.modeInfoIdx);
                var targetMode = FindModeInfo(modes, path.targetInfo.adapterId, path.targetInfo.id, DISPLAYCONFIG_MODE_INFO_TYPE_TARGET, path.targetInfo.modeInfoIdx);
                var targetName = TryGetTargetName(path.targetInfo.adapterId, path.targetInfo.id);

                var capture = new DisplayPathCapture {
                    AdapterKey = AdapterIdToString(path.targetInfo.adapterId),
                    SourceId = path.sourceInfo.id,
                    TargetId = path.targetInfo.id,
                    SourceDeviceName = TryGetSourceName(path.sourceInfo.adapterId, path.sourceInfo.id),
                    MonitorFriendlyName = targetName.HasValue ? targetName.Value.monitorFriendlyDeviceName : null,
                    MonitorDevicePath = targetName.HasValue ? targetName.Value.monitorDevicePath : null,
                    AdapterDevicePath = TryGetAdapterPath(path.targetInfo.adapterId),
                    IsActive = (path.flags & DISPLAYCONFIG_PATH_ACTIVE) == DISPLAYCONFIG_PATH_ACTIVE,
                    TargetAvailable = path.targetInfo.targetAvailable,
                    PathFlags = path.flags,
                    SourceStatusFlags = path.sourceInfo.statusFlags,
                    TargetStatusFlags = path.targetInfo.statusFlags,
                    Rotation = path.targetInfo.rotation,
                    Scaling = path.targetInfo.scaling,
                    OutputTechnology = path.targetInfo.outputTechnology,
                    ScanLineOrdering = path.targetInfo.scanLineOrdering,
                    RefreshRateNumerator = path.targetInfo.refreshRate.Numerator,
                    RefreshRateDenominator = path.targetInfo.refreshRate.Denominator,
                    HasSourceMode = sourceMode.HasValue,
                    HasTargetMode = targetMode.HasValue
                };

                if (sourceMode.HasValue) {
                    capture.SourceWidth = sourceMode.Value.modeInfo.sourceMode.width;
                    capture.SourceHeight = sourceMode.Value.modeInfo.sourceMode.height;
                    capture.SourcePositionX = sourceMode.Value.modeInfo.sourceMode.position.x;
                    capture.SourcePositionY = sourceMode.Value.modeInfo.sourceMode.position.y;
                    capture.PixelFormat = (int)sourceMode.Value.modeInfo.sourceMode.pixelFormat;
                }

                if (targetMode.HasValue) {
                    capture.TargetWidth = targetMode.Value.modeInfo.targetMode.targetVideoSignalInfo.activeSize.cx;
                    capture.TargetHeight = targetMode.Value.modeInfo.targetMode.targetVideoSignalInfo.activeSize.cy;
                    capture.PixelRate = targetMode.Value.modeInfo.targetMode.targetVideoSignalInfo.pixelRate;
                }

                captures.Add(capture);
            }

            return captures.ToArray();
        }

        public static MonitorCapture[] GetCurrentMonitors() {
            var monitors = new List<MonitorCapture>();
            EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr hMonitor, IntPtr hdcMonitor, ref RECT bounds, IntPtr dwData) => {
                var info = new MONITORINFOEX();
                info.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
                if (!GetMonitorInfo(hMonitor, ref info)) {
                    return true;
                }

                var devMode = new DEVMODE();
                devMode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
                EnumDisplaySettings(info.szDevice, ENUM_CURRENT_SETTINGS, ref devMode);

                var capture = new MonitorCapture {
                    DeviceName = info.szDevice,
                    IsPrimary = (info.dwFlags & 1U) == 1U,
                    Left = info.rcMonitor.Left,
                    Top = info.rcMonitor.Top,
                    Width = info.rcMonitor.Right - info.rcMonitor.Left,
                    Height = info.rcMonitor.Bottom - info.rcMonitor.Top,
                    WorkLeft = info.rcWork.Left,
                    WorkTop = info.rcWork.Top,
                    WorkWidth = info.rcWork.Right - info.rcWork.Left,
                    WorkHeight = info.rcWork.Bottom - info.rcWork.Top,
                    Orientation = devMode.dmDisplayOrientation,
                    BitsPerPel = devMode.dmBitsPerPel,
                    DisplayFrequency = devMode.dmDisplayFrequency,
                    HasEffectiveDpi = false
                };

                try {
                    uint dpiX;
                    uint dpiY;
                    if (GetDpiForMonitor(hMonitor, MDT_EFFECTIVE_DPI, out dpiX, out dpiY) == 0) {
                        capture.EffectiveDpiX = dpiX;
                        capture.EffectiveDpiY = dpiY;
                        capture.HasEffectiveDpi = true;
                    }
                }
                catch {
                }

                monitors.Add(capture);
                return true;
            }, IntPtr.Zero);

            return monitors.ToArray();
        }

        public static DisplayModeCapture[] GetDisplayModes(string deviceName) {
            var modes = new List<DisplayModeCapture>();
            var dedupe = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            for (var modeIndex = 0; modeIndex < 512; modeIndex++) {
                var mode = new DEVMODE();
                mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
                if (!EnumDisplaySettingsEx(deviceName, modeIndex, ref mode, 0)) {
                    break;
                }

                var capture = new DisplayModeCapture {
                    Width = mode.dmPelsWidth,
                    Height = mode.dmPelsHeight,
                    BitsPerPel = mode.dmBitsPerPel,
                    DisplayFrequency = mode.dmDisplayFrequency,
                    Orientation = mode.dmDisplayOrientation
                };

                var key = capture.Width + "x" + capture.Height + "|" + capture.DisplayFrequency + "|" + capture.Orientation + "|" + capture.BitsPerPel;
                if (dedupe.Add(key)) {
                    modes.Add(capture);
                }
            }

            return modes.ToArray();
        }

        public static uint GetPrimaryDpiScale() {
            foreach (var monitor in GetCurrentMonitors()) {
                if (monitor.IsPrimary) {
                    return GetDpiScaleForDevice(monitor.DeviceName);
                }
            }

            return 100;
        }

        public static uint GetDpiScaleForDevice(string deviceName) {
            if (string.IsNullOrWhiteSpace(deviceName)) {
                throw new ArgumentException("Device name is required.", nameof(deviceName));
            }

            LUID adapterId;
            uint sourceId;
            bool isPrimary;
            if (!TryResolveActiveSource(deviceName, out adapterId, out sourceId, out isPrimary)) {
                throw new InvalidOperationException("Active display source not found for '" + deviceName + "'.");
            }

            uint current;
            uint recommended;
            uint minimum;
            uint maximum;
            if (!TryGetDpiScalingInfo(adapterId, sourceId, out current, out recommended, out minimum, out maximum)) {
                throw new InvalidOperationException("Failed to query DPI scaling for '" + deviceName + "'.");
            }

            return current;
        }

        public static uint SetDpiScaleForDevice(string deviceName, uint dpiPercentToSet) {
            if (string.IsNullOrWhiteSpace(deviceName)) {
                throw new ArgumentException("Device name is required.", nameof(deviceName));
            }

            LUID adapterId;
            uint sourceId;
            bool isPrimary;
            if (!TryResolveActiveSource(deviceName, out adapterId, out sourceId, out isPrimary)) {
                throw new InvalidOperationException("Active display source not found for '" + deviceName + "'.");
            }

            uint current;
            uint recommended;
            uint minimum;
            uint maximum;
            if (!TryGetDpiScalingInfo(adapterId, sourceId, out current, out recommended, out minimum, out maximum)) {
                throw new InvalidOperationException("Failed to query DPI scaling for '" + deviceName + "'.");
            }

            var target = dpiPercentToSet;
            if (target < minimum) {
                target = minimum;
            }
            else if (target > maximum) {
                target = maximum;
            }

            if (target == current) {
                if (isPrimary) {
                    SetAppliedDpi(target);
                }

                return target;
            }

            var recommendedIndex = Array.IndexOf(DpiScaleValues, recommended);
            var targetIndex = Array.IndexOf(DpiScaleValues, target);
            if (recommendedIndex < 0 || targetIndex < 0) {
                throw new InvalidOperationException("Unsupported DPI scale value '" + target.ToString() + "'.");
            }

            var setPacket = new DISPLAYCONFIG_SOURCE_DPI_SCALE_SET();
            setPacket.header.adapterId = adapterId;
            setPacket.header.id = sourceId;
            setPacket.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DPI_SCALE_SET));
            setPacket.header.type = DISPLAYCONFIG_DEVICE_INFO_SET_DPI_SCALE;
            setPacket.scaleRel = targetIndex - recommendedIndex;
            ThrowIfWin32Error(DisplayConfigSetDeviceInfo(ref setPacket), "DisplayConfigSetDeviceInfo");

            if (isPrimary) {
                SetAppliedDpi(target);
            }

            return target;
        }

        public static DEVMODE GetDeviceMode(string deviceName, bool useRegistrySettings) {
            var mode = new DEVMODE();
            mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
            var modeNumber = useRegistrySettings ? ENUM_REGISTRY_SETTINGS : ENUM_CURRENT_SETTINGS;
            if (!EnumDisplaySettingsEx(deviceName, modeNumber, ref mode, 0)) {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "EnumDisplaySettingsEx failed.");
            }

            return mode;
        }

        public static int ApplyDeviceMode(string deviceName, DEVMODE mode, uint flags) {
            return ChangeDisplaySettingsEx(deviceName, ref mode, IntPtr.Zero, flags, IntPtr.Zero);
        }

        public static int ApplyPendingDisplayChanges() {
            return ChangeDisplaySettingsEx(null, IntPtr.Zero, IntPtr.Zero, 0, IntPtr.Zero);
        }
    }
}
"@
}

function Get-ParsecTextScalePercent {
    [CmdletBinding()]
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int] $ScalePercent
    )

    return [int] [Math]::Round(($ScalePercent / 100.0) * 96.0)
}

function ConvertTo-ParsecOrientationName {
    [CmdletBinding()]
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
    [CmdletBinding()]
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Arguments
    )

    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments
    $mode = Get-ParsecNativeDeviceMode -DeviceName $deviceName
    $mode.dmPelsWidth = [int] $Arguments.width
    $mode.dmPelsHeight = [int] $Arguments.height
    $mode.dmFields = $mode.dmFields -bor [ParsecEventExecutor.DisplayNative]::DM_PELSWIDTH -bor [ParsecEventExecutor.DisplayNative]::DM_PELSHEIGHT

    $result = Invoke-ParsecApplyDisplayMode -DeviceName $deviceName -Mode $mode -Action 'SetResolution' -Requested $Arguments
    if ($result.Status -eq 'Succeeded') {
        $result.Message = "Set resolution for '$deviceName' to $($Arguments.width)x$($Arguments.height)."
    }

    return $result
}

function Set-ParsecDisplayOrientationInternal {
    [CmdletBinding()]
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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Arguments
    )

    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments
    $mode = Get-ParsecNativeDeviceMode -DeviceName $deviceName
    $enable = [bool] $Arguments.enabled

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
        $stateName = if ($enable) { 'enabled' } else { 'disabled' }
        $result.Message = "Monitor '$deviceName' $stateName."
    }

    return $result
}

function Set-ParsecDisplayPrimaryInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Arguments
    )

    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments
    $mode = Get-ParsecNativeDeviceMode -DeviceName $deviceName
    $mode.dmPositionX = 0
    $mode.dmPositionY = 0
    $mode.dmFields = $mode.dmFields -bor [ParsecEventExecutor.DisplayNative]::DM_POSITION

    $result = Invoke-ParsecApplyDisplayMode -DeviceName $deviceName -Mode $mode -Flags ([int] [ParsecEventExecutor.DisplayNative]::CDS_SET_PRIMARY) -Action 'SetPrimary' -Requested $Arguments
    if ($result.Status -eq 'Succeeded') {
        $result.Message = "Monitor '$deviceName' set as primary."
    }

    return $result
}

function Get-ParsecThemeState {
    [CmdletBinding()]
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
    param()

    Initialize-ParsecDisplayInterop
}

function Set-ParsecThemeStateInternal {
    [CmdletBinding()]
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
    [ParsecEventExecutor.DisplayNative]::BroadcastSettingChange('ImmersiveColorSet')
    [ParsecEventExecutor.DisplayNative]::BroadcastSettingChange('WindowsThemeElement')

    $state = Get-ParsecThemeState
    return New-ParsecResult -Status 'Succeeded' -Message ("Theme set to app={0}, system={1}." -f $state.app_mode, $state.system_mode) -Observed $state -Outputs @{
        theme_state = $state
    }
}

function Set-ParsecWallpaperStateInternal {
    [CmdletBinding()]
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
    [ParsecEventExecutor.DisplayNative]::BroadcastSettingChange('Control Panel\Desktop')
    [ParsecEventExecutor.DisplayNative]::BroadcastSettingChange('Environment')

    $state = Get-ParsecWallpaperState
    return New-ParsecResult -Status 'Succeeded' -Message 'Wallpaper state restored.' -Observed $state -Outputs @{
        wallpaper_state = $state
    }
}

function Set-ParsecTextScaleStateInternal {
    [CmdletBinding()]
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

    New-ItemProperty -Path $path -Name 'TextScaleFactor' -Value $textScalePercent -PropertyType DWord -Force | Out-Null
    Initialize-ParsecPersonalizationInterop
    [ParsecEventExecutor.DisplayNative]::BroadcastSettingChange('Accessibility')
    [ParsecEventExecutor.DisplayNative]::BroadcastSettingChange('WindowMetrics')
    [ParsecEventExecutor.DisplayNative]::BroadcastSettingChange('Control Panel\Desktop')

    return New-ParsecResult -Status 'Succeeded' -Message "Text scaling set to $textScalePercent%." -Observed @{
        text_scale_percent = $textScalePercent
    } -Outputs @{
        text_scale_percent = $textScalePercent
    }
}

function Set-ParsecUiScaleStateInternal {
    [CmdletBinding()]
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
    param()

    if (Get-Variable -Name ParsecPersonalizationAdapter -Scope Script -ErrorAction SilentlyContinue) {
        return
    }

    $script:ParsecPersonalizationAdapter = @{
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
    }
}

function Invoke-ParsecPersonalizationAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Method,

        [Parameter()]
        [hashtable] $Arguments = @{}
    )

    Initialize-ParsecPersonalizationAdapter
    if (-not $script:ParsecPersonalizationAdapter.ContainsKey($Method)) {
        throw "Personalization adapter method '$Method' is not available."
    }

    return & $script:ParsecPersonalizationAdapter[$Method] $Arguments
}

function Get-ParsecWindowCaptureState {
    [CmdletBinding()]
    param()

    $foreground = $null
    foreach ($attempt in 1..5) {
        $foreground = Invoke-ParsecWindowAdapter -Method 'GetForegroundWindowInfo'
        if ($null -ne $foreground -and $foreground.handle) {
            break
        }

        Start-Sleep -Milliseconds 100
    }

    $windows = @(Get-ParsecAltTabCandidateWindows)

    return [ordered]@{
        captured_at = [DateTimeOffset]::UtcNow.ToString('o')
        foreground_window = ConvertTo-ParsecPlainObject -InputObject $foreground
        windows = @($windows | ForEach-Object { ConvertTo-ParsecPlainObject -InputObject $_ })
    }
}

function Test-ParsecWindowActivationCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Window,

        [Parameter()]
        [bool] $IncludeMinimized = $false
    )

    if ($null -eq $Window.handle -or [int64] $Window.handle -eq 0) {
        return $false
    }

    if ($Window.Contains('is_shell_window') -and [bool] $Window.is_shell_window) {
        return $false
    }

    if ($Window.Contains('is_visible') -and -not [bool] $Window.is_visible) {
        return $false
    }

    if ($Window.Contains('is_cloaked') -and [bool] $Window.is_cloaked) {
        return $false
    }

    if (-not $IncludeMinimized -and $Window.Contains('is_minimized') -and [bool] $Window.is_minimized) {
        return $false
    }

    $title = if ($Window.Contains('title')) { [string] $Window.title } else { '' }
    if ([string]::IsNullOrWhiteSpace($title)) {
        return $false
    }

    $className = if ($Window.Contains('class_name')) { [string] $Window.class_name } else { '' }
    if ($className -in @('IME', 'tooltips_class32', 'SysShadow', 'ForegroundStaging', 'ThumbnailDeviceHelperWnd', 'PseudoConsoleWindow')) {
        return $false
    }

    $processName = if ($Window.Contains('process_name')) { [string] $Window.process_name } else { '' }
    if ($processName -eq 'ApplicationFrameHost') {
        return $false
    }

    if ($title -eq 'Windows Input Experience' -or $processName -eq 'TextInputHost') {
        return $false
    }

    $extendedStyle = if ($Window.Contains('extended_style') -and $null -ne $Window.extended_style) { [int64] $Window.extended_style } else { 0 }
    $ownerHandle = if ($Window.Contains('owner_handle') -and $null -ne $Window.owner_handle) { [int64] $Window.owner_handle } else { 0 }
    $hasAppWindowStyle = ($extendedStyle -band 0x40000) -ne 0
    $hasToolWindowStyle = ($extendedStyle -band 0x80) -ne 0
    $hasNoActivateStyle = ($extendedStyle -band 0x08000000) -ne 0
    $hasTopMostStyle = ($extendedStyle -band 0x8) -ne 0

    $width = if ($Window.Contains('width') -and $null -ne $Window.width) { [int] $Window.width } else { 0 }
    $height = if ($Window.Contains('height') -and $null -ne $Window.height) { [int] $Window.height } else { 0 }
    if ($width -gt 0 -and $height -gt 0 -and ($width -lt 64 -or $height -lt 64)) {
        return $false
    }

    if (($extendedStyle -band 0x80) -ne 0) {
        return $false
    }

    if ($hasNoActivateStyle) {
        return $false
    }

    if ($ownerHandle -ne 0 -and -not $hasAppWindowStyle) {
        return $false
    }

    if ($hasToolWindowStyle) {
        return $false
    }

    if ($hasTopMostStyle) {
        return $false
    }

    return $true
}

function Get-ParsecAltTabCandidateWindows {
    [CmdletBinding()]
    param(
        [Parameter()]
        [bool] $IncludeMinimized = $false
    )

    $windows = @(Invoke-ParsecWindowAdapter -Method 'GetTopLevelWindows')
    return @(
        foreach ($window in $windows) {
            if (Test-ParsecWindowActivationCandidate -Window $window -IncludeMinimized:$IncludeMinimized) {
                ConvertTo-ParsecPlainObject -InputObject $window
            }
        }
    )
}

function Invoke-ParsecWindowCycleInternal {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{}
    )

    $dwellMilliseconds = if ($Arguments.ContainsKey('dwell_ms')) { [int] $Arguments.dwell_ms } else { 100 }
    if ($dwellMilliseconds -lt 0) {
        throw 'dwell_ms must be zero or greater.'
    }

    $maxCycles = if ($Arguments.ContainsKey('max_cycles')) { [int] $Arguments.max_cycles } else { 30 }
    if ($maxCycles -lt 1) {
        throw 'max_cycles must be one or greater.'
    }

    $captureState = Get-ParsecWindowCaptureState
    $foregroundWindow = if ($captureState.Contains('foreground_window')) { ConvertTo-ParsecPlainObject -InputObject $captureState.foreground_window } else { $null }
    $foregroundHandle = if ($foregroundWindow -is [System.Collections.IDictionary] -and $foregroundWindow.Contains('handle') -and $null -ne $foregroundWindow.handle) { [int64] $foregroundWindow.handle } else { 0 }
    if ($foregroundHandle -eq 0) {
        return New-ParsecResult -Status 'Failed' -Message 'Could not capture the current foreground window.' -Errors @('MissingForegroundWindow')
    }

    $altTabCandidates = if ($captureState.Contains('windows')) { @($captureState.windows) } else { @() }
    $candidateHandles = @($altTabCandidates | ForEach-Object { if ($_ -is [System.Collections.IDictionary] -and $_.Contains('handle')) { [int64] $_.handle } })
    if ($candidateHandles.Count -eq 0) {
        return New-ParsecResult -Status 'Failed' -Message 'No Alt-Tab candidate windows were available to cycle.' -Observed @{
            foreground_window = $foregroundWindow
        } -Errors @('MissingAltTabCandidates')
    }

    if (-not ($candidateHandles -contains $foregroundHandle)) {
        return New-ParsecResult -Status 'Failed' -Message 'The current foreground window is not an Alt-Tab candidate.' -Observed @{
            foreground_window = $foregroundWindow
            candidate_handles = @($candidateHandles)
        } -Errors @('ForegroundNotAltTabCandidate')
    }

    $activationResults = New-Object System.Collections.ArrayList
    $candidateSequence = @($altTabCandidates | Where-Object {
            $_ -is [System.Collections.IDictionary] -and
            $_.Contains('handle') -and
            [int64] $_.handle -ne $foregroundHandle
        })
    if ($candidateSequence.Count -gt $maxCycles) {
        $candidateSequence = @($candidateSequence | Select-Object -First $maxCycles)
    }

    $activationSucceeded = $true
    $cycle = 0
    foreach ($candidate in $candidateSequence) {
        $cycle++
        $activation = Invoke-ParsecWindowAdapter -Method 'ActivateWindow' -Arguments @{
            handle = [int64] $candidate.handle
            restore_if_minimized = $false
        }
        $currentForeground = Invoke-ParsecWindowAdapter -Method 'GetForegroundWindowInfo'
        $stepRecord = [ordered]@{
            cycle = $cycle
            candidate = ConvertTo-ParsecPlainObject -InputObject $candidate
            activation = ConvertTo-ParsecPlainObject -InputObject $activation
            foreground_window = ConvertTo-ParsecPlainObject -InputObject $currentForeground
        }
        [void] $activationResults.Add($stepRecord)
        if (-not $activation.succeeded) {
            $activationSucceeded = $false
            break
        }

        if ($dwellMilliseconds -gt 0) {
            Start-Sleep -Milliseconds $dwellMilliseconds
        }
    }

    $restoreResult = Invoke-ParsecWindowAdapter -Method 'ActivateWindow' -Arguments @{
        handle = $foregroundHandle
        restore_if_minimized = $false
    }
    $restoredForeground = Invoke-ParsecWindowAdapter -Method 'GetForegroundWindowInfo'
    $restoredHandle = if ($null -ne $restoredForeground -and $restoredForeground.handle) { [int64] $restoredForeground.handle } else { 0 }
    $loopReturned = $restoreResult.succeeded -and $restoredHandle -eq $foregroundHandle

    $status = if ($activationSucceeded -and $loopReturned) { 'Succeeded' } else { 'Failed' }
    $message = if ($status -eq 'Succeeded') { 'Window activation cycle completed and restored the original foreground window.' } elseif (-not $activationSucceeded) { 'Window activation cycle failed while activating an Alt-Tab candidate.' } else { 'Window activation cycle completed, but the original foreground window could not be restored.' }
    $errors = @()
    if (-not $activationSucceeded) {
        $errors += 'WindowActivationFailed'
    }
    if (-not $loopReturned) {
        $errors += 'ForegroundRestoreFailed'
    }

    return New-ParsecResult -Status $status -Message $message -Observed @{
        original_foreground_handle = $foregroundHandle
        alt_tab_candidate_count = $candidateHandles.Count
        cycle_count = @($activationResults).Count
        loop_returned = $loopReturned
    } -Outputs @{
        captured_state = @{
            foreground_window = $foregroundWindow
            windows = @($altTabCandidates)
        }
        original_foreground_window = $foregroundWindow
        alt_tab_candidates = @($altTabCandidates)
        activation_results = @($activationResults)
        restore_result = ConvertTo-ParsecPlainObject -InputObject $restoreResult
        dwell_ms = $dwellMilliseconds
        max_cycles = $maxCycles
    } -Errors $errors
}

function Restore-ParsecWindowForegroundInternal {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -eq $capturedState -or -not $capturedState.Contains('foreground_window') -or $null -eq $capturedState.foreground_window) {
        return New-ParsecResult -Status 'Succeeded' -Message 'No captured foreground window was available to restore.' -Outputs @{
            restored = $false
        }
    }

    $foregroundWindow = $capturedState.foreground_window
    if (-not ($foregroundWindow -is [System.Collections.IDictionary]) -or -not $foregroundWindow.Contains('handle')) {
        return New-ParsecResult -Status 'Succeeded' -Message 'No captured foreground window was available to restore.' -Outputs @{
            restored = $false
        }
    }

    $activation = Invoke-ParsecWindowAdapter -Method 'ActivateWindow' -Arguments @{
        handle = [int64] $foregroundWindow.handle
        restore_if_minimized = $true
    }

    if (-not $activation.succeeded) {
        return New-ParsecResult -Status 'Failed' -Message 'Failed to restore the original foreground window.' -Observed (ConvertTo-ParsecPlainObject -InputObject $activation) -Outputs @{
            restored = $false
        } -Errors @('ForegroundRestoreFailed')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Restored the original foreground window.' -Observed (ConvertTo-ParsecPlainObject -InputObject $activation.window) -Outputs @{
        restored = $true
        restored_window = ConvertTo-ParsecPlainObject -InputObject $activation.window
    }
}

function Initialize-ParsecWindowAdapter {
    [CmdletBinding()]
    param()

    if (Get-Variable -Name ParsecWindowAdapter -Scope Script -ErrorAction SilentlyContinue) {
        return
    }

    $script:ParsecWindowAdapter = @{
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
    }
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
    if (-not $script:ParsecWindowAdapter.ContainsKey($Method)) {
        throw "Window adapter method '$Method' is not available."
    }

    return & $script:ParsecWindowAdapter[$Method] $Arguments
}

function Get-ParsecDisplayIdentityKey {
    [CmdletBinding()]
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

function Get-ParsecDisplayCaptureResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ObservedState,

        [Parameter()]
        [string] $DeviceName,

        [Parameter(Mandatory)]
        [string] $Domain
    )

    if ($DeviceName) {
        $monitor = Get-ParsecObservedMonitor -ObservedState $ObservedState -DeviceName $DeviceName
        if ($null -eq $monitor) {
            return New-ParsecResult -Status 'Failed' -Message "Monitor '$DeviceName' not found." -Observed $ObservedState -Errors @('MonitorNotFound')
        }

        return New-ParsecResult -Status 'Succeeded' -Message "Captured $Domain state for '$DeviceName'." -Observed $monitor -Outputs @{
            captured_state = $monitor
            device_name = $DeviceName
            domain = $Domain
        }
    }

    return New-ParsecResult -Status 'Succeeded' -Message "Captured $Domain state." -Observed $ObservedState -Outputs @{
        captured_state = $ObservedState
        domain = $Domain
    }
}

function Get-ParsecDisplayTopologyCaptureState {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $ObservedState = $(Get-ParsecObservedState)
    )

    $monitors = foreach ($monitor in @($ObservedState.monitors)) {
        [ordered]@{
            device_name = [string] $monitor.device_name
            source_name = if ($monitor.Contains('source_name')) { [string] $monitor.source_name } else { $null }
            friendly_name = if ($monitor.Contains('friendly_name')) { [string] $monitor.friendly_name } else { $null }
            monitor_device_path = if ($monitor.Contains('monitor_device_path')) { [string] $monitor.monitor_device_path } else { $null }
            adapter_device_path = if ($monitor.Contains('adapter_device_path')) { [string] $monitor.adapter_device_path } else { $null }
            adapter_id = if ($monitor.Contains('adapter_id')) { [string] $monitor.adapter_id } else { $null }
            source_id = if ($monitor.Contains('source_id')) { [int] $monitor.source_id } else { $null }
            target_id = if ($monitor.Contains('target_id')) { [int] $monitor.target_id } else { $null }
            is_primary = [bool] $monitor.is_primary
            enabled = [bool] $monitor.enabled
            target_available = if ($monitor.Contains('target_available')) { [bool] $monitor.target_available } else { $null }
            bounds = if ($monitor.Contains('bounds')) {
                [ordered]@{
                    x = $monitor.bounds.x
                    y = $monitor.bounds.y
                    width = $monitor.bounds.width
                    height = $monitor.bounds.height
                }
            }
            else {
                $null
            }
            orientation = if ($monitor.Contains('orientation')) { [string] $monitor.orientation } else { $null }
            identity = if ($monitor.Contains('identity')) {
                ConvertTo-ParsecPlainObject -InputObject $monitor.identity
            }
            else {
                $null
            }
            topology = if ($monitor.Contains('topology')) {
                ConvertTo-ParsecPlainObject -InputObject $monitor.topology
            }
            else {
                $null
            }
            display = if ($monitor.Contains('display')) {
                [ordered]@{
                    width = $monitor.display.width
                    height = $monitor.display.height
                    bits_per_pel = $monitor.display.bits_per_pel
                    refresh_rate_hz = $monitor.display.refresh_rate_hz
                }
            }
            else {
                $null
            }
        }
    }

    return [ordered]@{
        captured_at = if ($ObservedState.Contains('captured_at')) { [string] $ObservedState.captured_at } else { [DateTimeOffset]::UtcNow.ToString('o') }
        computer_name = if ($ObservedState.Contains('computer_name')) { [string] $ObservedState.computer_name } else { $env:COMPUTERNAME }
        display_backend = if ($ObservedState.Contains('display_backend')) { [string] $ObservedState.display_backend } else { $null }
        monitor_identity = if ($ObservedState.Contains('monitor_identity')) { [string] $ObservedState.monitor_identity } else { $null }
        monitors = @($monitors)
        topology = if ($ObservedState.Contains('topology')) {
            ConvertTo-ParsecPlainObject -InputObject $ObservedState.topology
        }
        else {
            [ordered]@{
                query_mode = 'Unknown'
                path_count = 0
                paths = @()
            }
        }
    }
}

function Invoke-ParsecDisplayTopologyReset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $TopologyState,

        [Parameter()]
        [string] $SnapshotName = ''
    )

    $actions = New-Object System.Collections.Generic.List[object]
    foreach ($monitor in @($TopologyState.monitors)) {
        $isEnabled = [bool] $monitor.enabled
        $targetAvailable = if ($monitor.Contains('target_available') -and $null -ne $monitor.target_available) {
            [bool] $monitor.target_available
        }
        else {
            $true
        }

        if (-not $isEnabled -and -not $targetAvailable) {
            continue
        }

        $enableArguments = @{
            device_name = [string] $monitor.device_name
            enabled = $isEnabled
        }
        if ($monitor.Contains('bounds') -and $monitor.bounds -is [System.Collections.IDictionary]) {
            $enableArguments.bounds = ConvertTo-ParsecPlainObject -InputObject $monitor.bounds
        }

        $actions.Add((Invoke-ParsecDisplayAdapter -Method 'SetEnabled' -Arguments $enableArguments))
    }

    foreach ($monitor in @($TopologyState.monitors)) {
        $isEnabled = [bool] $monitor.enabled
        $targetAvailable = if ($monitor.Contains('target_available') -and $null -ne $monitor.target_available) {
            [bool] $monitor.target_available
        }
        else {
            $true
        }

        if ($isEnabled -and $targetAvailable -and $monitor.Contains('orientation') -and -not [string]::IsNullOrWhiteSpace([string] $monitor.orientation) -and $monitor.orientation -ne 'Unknown') {
            $actions.Add((Invoke-ParsecDisplayAdapter -Method 'SetOrientation' -Arguments @{
                        device_name = [string] $monitor.device_name
                        orientation = [string] $monitor.orientation
                    }))
        }
    }

    foreach ($monitor in @($TopologyState.monitors)) {
        $isEnabled = [bool] $monitor.enabled
        $targetAvailable = if ($monitor.Contains('target_available') -and $null -ne $monitor.target_available) {
            [bool] $monitor.target_available
        }
        else {
            $true
        }

        if ($isEnabled -and $targetAvailable -and $monitor.Contains('is_primary') -and [bool] $monitor.is_primary) {
            $actions.Add((Invoke-ParsecDisplayAdapter -Method 'SetPrimary' -Arguments @{
                        device_name = [string] $monitor.device_name
                    }))
        }
    }

    $actionResults = @($actions | Where-Object { $null -ne $_ } | ForEach-Object { $_ })
    if ($actionResults.Count -ne $actions.Count) {
        return New-ParsecResult -Status 'Failed' -Message 'Display topology restore produced an incomplete action result set.' -Outputs @{
            snapshot_name = $SnapshotName
            actions = $actionResults
        } -Errors @('ResetFailed')
    }

    $failures = @($actionResults | Where-Object { -not (Test-ParsecSuccessfulStatus -Status $_.Status) })
    if ($failures.Count -gt 0) {
        return New-ParsecResult -Status 'Failed' -Message $failures[0].Message -Outputs @{
            snapshot_name = $SnapshotName
            actions = $actionResults
        } -Errors @('ResetFailed')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Display topology restored.' -Outputs @{
        snapshot_name = $SnapshotName
        actions = $actionResults
    }
}

function Compare-ParsecDisplayTopologyState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $TargetState,

        [Parameter(Mandatory)]
        [hashtable] $ObservedState
    )

    $mismatches = New-Object System.Collections.Generic.List[string]
    foreach ($targetMonitor in @($TargetState.monitors)) {
        $observedMonitor = Get-ParsecObservedMonitor -ObservedState $ObservedState -DeviceName ([string] $targetMonitor.device_name)
        if ($null -eq $observedMonitor) {
            $mismatches.Add("Monitor '$($targetMonitor.device_name)' not found.")
            continue
        }

        if ([bool] $targetMonitor.enabled -ne [bool] $observedMonitor.enabled) {
            $mismatches.Add("Monitor '$($targetMonitor.device_name)' enabled state mismatch.")
        }

        if ([bool] $targetMonitor.is_primary -ne [bool] $observedMonitor.is_primary) {
            $mismatches.Add("Monitor '$($targetMonitor.device_name)' primary state mismatch.")
        }

        if ($targetMonitor.Contains('bounds') -and $targetMonitor.bounds -is [System.Collections.IDictionary]) {
            if ($targetMonitor.bounds.x -ne $observedMonitor.bounds.x -or $targetMonitor.bounds.y -ne $observedMonitor.bounds.y) {
                $mismatches.Add("Monitor '$($targetMonitor.device_name)' position mismatch.")
            }

            if ($targetMonitor.bounds.width -ne $observedMonitor.bounds.width -or $targetMonitor.bounds.height -ne $observedMonitor.bounds.height) {
                $mismatches.Add("Monitor '$($targetMonitor.device_name)' resolution mismatch.")
            }
        }

        if ($targetMonitor.Contains('orientation') -and -not [string]::IsNullOrWhiteSpace([string] $targetMonitor.orientation) -and $targetMonitor.orientation -ne 'Unknown' -and $targetMonitor.orientation -ne $observedMonitor.orientation) {
            $mismatches.Add("Monitor '$($targetMonitor.device_name)' orientation mismatch.")
        }
    }

    if ($mismatches.Count -gt 0) {
        return New-ParsecResult -Status 'Failed' -Message ($mismatches -join ' ') -Observed $ObservedState -Outputs @{
            mismatches = @($mismatches)
            target_state = $TargetState
        }
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Observed display topology matches the target topology.' -Observed $ObservedState -Outputs @{
        target_state = $TargetState
    }
}

function Compare-ParsecActiveDisplaySelectionState {
    [CmdletBinding()]
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
        $monitor = Resolve-ParsecDisplayMonitorByScreenId -ObservedState $ObservedState -ScreenId ([int] $screenId) -StateRoot $StateRoot
        if ($null -eq $monitor) {
            return New-ParsecResult -Status 'Failed' -Message "Screen id '$screenId' could not be resolved." -Observed $ObservedState -Errors @('MonitorNotFound')
        }

        $identityKey = Get-ParsecDisplayMonitorIdentityKey -Monitor $monitor
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

    $targetState = Get-ParsecDisplayTopologyCaptureState -ObservedState $ObservedState
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

    $observed = Get-ParsecObservedState
    $resolution = Resolve-ParsecActiveDisplayTargetState -ObservedState $observed -Arguments $Arguments -StateRoot $StateRoot
    if (-not (Test-ParsecSuccessfulStatus -Status $resolution.Status)) {
        return $resolution
    }

    return ConvertTo-ParsecPlainObject -InputObject $resolution.Outputs.target_state
}

function Get-ParsecCapturedStateFromResult {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    if ($Arguments.ContainsKey('captured_state') -and $Arguments.captured_state -is [System.Collections.IDictionary]) {
        return ConvertTo-ParsecPlainObject -InputObject $Arguments.captured_state
    }

    if ($null -ne $ExecutionResult -and $ExecutionResult.Outputs -and $ExecutionResult.Outputs.captured_state) {
        return ConvertTo-ParsecPlainObject -InputObject $ExecutionResult.Outputs.captured_state
    }

    return $null
}

function Get-ParsecDisplayResetMonitorState {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $Preference = 'requested'
    )

    $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -eq $capturedState) {
        return $null
    }

    if ($Preference -eq 'primary' -and $capturedState.Contains('primary_monitor')) {
        return $capturedState.primary_monitor
    }

    if ($capturedState.Contains('requested_monitor')) {
        return $capturedState.requested_monitor
    }

    return $capturedState
}

function Get-ParsecProcessCaptureResult {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{}
    )

    $process = $null
    if ($Arguments.ContainsKey('process_id')) {
        $process = Get-Process -Id ([int] $Arguments.process_id) -ErrorAction SilentlyContinue
    }
    elseif ($Arguments.ContainsKey('process_name')) {
        $process = @(Get-Process -Name $Arguments.process_name -ErrorAction SilentlyContinue) | Select-Object -First 1
    }
    elseif ($Arguments.ContainsKey('file_path')) {
        $processName = [System.IO.Path]::GetFileNameWithoutExtension([string] $Arguments.file_path)
        if (-not [string]::IsNullOrWhiteSpace($processName)) {
            $process = @(Get-Process -Name $processName -ErrorAction SilentlyContinue) | Select-Object -First 1
        }
    }

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

function Get-ParsecServiceCaptureResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Arguments
    )

    $service = Get-Service -Name $Arguments.service_name -ErrorAction Stop
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

function Initialize-ParsecDisplayAdapter {
    [CmdletBinding()]
    param()

    if (Get-Variable -Name ParsecDisplayAdapter -Scope Script -ErrorAction SilentlyContinue) {
        return
    }

    $script:ParsecDisplayAdapter = @{
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

function Initialize-ParsecNvidiaAdapter {
    [CmdletBinding()]
    param()

    if (Get-Variable -Name ParsecNvidiaAdapter -Scope Script -ErrorAction SilentlyContinue) {
        return
    }

    $script:ParsecNvidiaAdapter = @{
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
    }
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
    if (-not $script:ParsecNvidiaAdapter.ContainsKey($Method)) {
        throw "NVIDIA adapter method '$Method' is not available."
    }

    return & $script:ParsecNvidiaAdapter[$Method] $Arguments
}

function Get-ParsecObservedState {
    [CmdletBinding()]
    param()

    return Invoke-ParsecDisplayAdapter -Method 'GetObservedState'
}

function Get-ParsecObservedMonitor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $ObservedState,

        [Parameter(Mandatory)]
        [string] $DeviceName
    )

    return @($ObservedState.monitors) | Where-Object { $_.device_name -eq $DeviceName } | Select-Object -First 1
}

function Resolve-ParsecDisplayTargetMonitor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ObservedState,

        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    if ($Arguments.ContainsKey('screen_id') -and $null -ne $Arguments.screen_id) {
        return Resolve-ParsecDisplayMonitorByScreenId -ObservedState $ObservedState -ScreenId ([int] $Arguments.screen_id) -StateRoot $StateRoot
    }

    if ($Arguments.ContainsKey('device_name') -and -not [string]::IsNullOrWhiteSpace([string] $Arguments.device_name)) {
        return Get-ParsecObservedMonitor -ObservedState $ObservedState -DeviceName ([string] $Arguments.device_name)
    }

    if ($Arguments.ContainsKey('monitor_device_path') -and -not [string]::IsNullOrWhiteSpace([string] $Arguments.monitor_device_path)) {
        return @($ObservedState.monitors) | Where-Object { $_.monitor_device_path -eq [string] $Arguments.monitor_device_path } | Select-Object -First 1
    }

    return @($ObservedState.monitors) | Where-Object { $_.is_primary } | Select-Object -First 1
}

function Resolve-ParsecDisplayTargetDeviceName {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    if ($Arguments.ContainsKey('device_name') -and -not [string]::IsNullOrWhiteSpace([string] $Arguments.device_name)) {
        return [string] $Arguments.device_name
    }

    $observed = Get-ParsecObservedState
    $targetMonitor = Resolve-ParsecDisplayTargetMonitor -ObservedState $observed -Arguments $Arguments -StateRoot $StateRoot
    if ($null -eq $targetMonitor) {
        throw 'Could not resolve a target display device.'
    }

    return [string] $targetMonitor.device_name
}

function Get-ParsecSupportedDisplayModes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $DeviceName
    )

    if (
        (Get-Variable -Name ParsecDisplayAdapter -Scope Script -ErrorAction SilentlyContinue) -and
        $script:ParsecDisplayAdapter.ContainsKey('GetSupportedModes')
    ) {
        return @(& $script:ParsecDisplayAdapter.GetSupportedModes @{ device_name = $DeviceName })
    }

    Initialize-ParsecDisplayInterop
    $modes = @([ParsecEventExecutor.DisplayNative]::GetDisplayModes($DeviceName))
    return @(
        foreach ($mode in $modes) {
            [ordered]@{
                width = [int] $mode.Width
                height = [int] $mode.Height
                bits_per_pel = [int] $mode.BitsPerPel
                refresh_rate_hz = [int] $mode.DisplayFrequency
                orientation = ConvertTo-ParsecOrientationName -Orientation ([int] $mode.Orientation)
            }
        }
    )
}

function Compare-ParsecDisplayState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $TargetState,

        [Parameter(Mandatory)]
        [hashtable] $ObservedState
    )

    $mismatches = New-Object System.Collections.Generic.List[string]
    foreach ($targetMonitor in @($TargetState.monitors)) {
        $observedMonitor = Get-ParsecObservedMonitor -ObservedState $ObservedState -DeviceName $targetMonitor.device_name
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

    if ($TargetState.Contains('scaling') -and $TargetState.scaling.Contains('value')) {
        if (-not $ObservedState.Contains('scaling') -or $ObservedState.scaling.value -ne $TargetState.scaling.value) {
            $mismatches.Add('Display scaling mismatch.')
        }
    }

    if ($TargetState.Contains('font_scaling') -and $TargetState.font_scaling.Contains('text_scale_percent')) {
        if (-not $ObservedState.Contains('font_scaling') -or $ObservedState.font_scaling.text_scale_percent -ne $TargetState.font_scaling.text_scale_percent) {
            $mismatches.Add('Font scaling mismatch.')
        }
    }

    if ($TargetState.Contains('theme')) {
        if (-not $ObservedState.Contains('theme')) {
            $mismatches.Add('Theme state is missing.')
        }
        else {
            if ($TargetState.theme.Contains('app_mode') -and $ObservedState.theme.app_mode -ne $TargetState.theme.app_mode) {
                $mismatches.Add('Application theme mismatch.')
            }

            if ($TargetState.theme.Contains('system_mode') -and $ObservedState.theme.system_mode -ne $TargetState.theme.system_mode) {
                $mismatches.Add('System theme mismatch.')
            }
        }
    }

    if ($mismatches.Count -gt 0) {
        return New-ParsecResult -Status 'Failed' -Message ($mismatches -join ' ') -Observed $ObservedState -Outputs @{ mismatches = @($mismatches) }
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Observed state matches the target state.' -Observed $ObservedState -Outputs @{ target_state = $TargetState }
}

function Resolve-ParsecSnapshotName {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{},

        [Parameter()]
        [switch] $UseDefaultCaptureName
    )

    if ($Arguments.ContainsKey('snapshot_name') -and -not [string]::IsNullOrWhiteSpace($Arguments.snapshot_name)) {
        return [string] $Arguments.snapshot_name
    }

    if ($RunState.ContainsKey('active_snapshot') -and -not [string]::IsNullOrWhiteSpace($RunState.active_snapshot)) {
        return [string] $RunState.active_snapshot
    }

    $executorState = Get-ParsecExecutorStateDocument -StateRoot $StateRoot
    if ($executorState.active_snapshot) {
        return [string] $executorState.active_snapshot
    }

    if ($UseDefaultCaptureName.IsPresent) {
        return 'desktop-pre-parsec'
    }

    throw 'No active snapshot is available.'
}

function Get-ParsecSnapshotTarget {
    [CmdletBinding()]
    param(
        [Parameter()]
        [hashtable] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{}
    )

    $snapshotName = Resolve-ParsecSnapshotName -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState
    $snapshot = Read-ParsecSnapshotDocument -Name $snapshotName -StateRoot $StateRoot
    return [ordered]@{
        snapshot_name = $snapshotName
        snapshot = $snapshot
    }
}

function Invoke-ParsecSnapshotReset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $SnapshotDocument
    )

    $topologyResult = Invoke-ParsecDisplayTopologyReset -TopologyState (Get-ParsecDisplayTopologyCaptureState -ObservedState $SnapshotDocument.display) -SnapshotName ([string] $SnapshotDocument.name)
    $actions = New-Object System.Collections.Generic.List[object]
    foreach ($actionResult in @($topologyResult.Outputs.actions)) {
        $actions.Add($actionResult)
    }

    if ($SnapshotDocument.display.Contains('font_scaling') -and $SnapshotDocument.display.font_scaling.Contains('text_scale_percent')) {
        $actions.Add((Invoke-ParsecDisplayAdapter -Method 'SetScaling' -Arguments @{ text_scale_percent = [int] $SnapshotDocument.display.font_scaling.text_scale_percent }))
    }

    if ($SnapshotDocument.display.Contains('theme')) {
        $actions.Add((Invoke-ParsecPersonalizationAdapter -Method 'SetThemeState' -Arguments @{ theme_state = $SnapshotDocument.display.theme }))
    }

    if ($SnapshotDocument.display.Contains('wallpaper')) {
        $actions.Add((Invoke-ParsecPersonalizationAdapter -Method 'SetWallpaperState' -Arguments @{ wallpaper_state = $SnapshotDocument.display.wallpaper }))
    }

    $actionResults = @($actions | ForEach-Object { $_ })
    $failures = @($actionResults | Where-Object { -not (Test-ParsecSuccessfulStatus -Status $_.Status) })
    if ($failures.Count -gt 0) {
        return New-ParsecResult -Status 'Failed' -Message $failures[0].Message -Outputs @{ snapshot_name = [string] $SnapshotDocument.name; actions = $actionResults } -Errors @('ResetFailed')
    }

    return New-ParsecResult -Status 'Succeeded' -Message "Snapshot '$($SnapshotDocument.name)' restored." -Outputs @{ snapshot_name = [string] $SnapshotDocument.name; actions = $actionResults }
}

function Test-ParsecIngredientOperationSupported {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Definition,

        [Parameter(Mandatory)]
        [string] $Operation
    )

    return $Definition.Operations.ContainsKey($Operation)
}

function Invoke-ParsecIngredientOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Operation,

        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{}
    )

    $definition = Get-ParsecIngredientDefinition -Name $Name
    if (-not (Test-ParsecIngredientOperationSupported -Definition $definition -Operation $Operation)) {
        throw "Ingredient '$Name' does not support operation '$Operation'."
    }

    Assert-ParsecIngredientArguments -Definition $definition -Operation $Operation -Arguments $Arguments
    $handler = $definition.Operations[$Operation]
    return & $handler $Arguments $ExecutionResult $StateRoot $RunState $definition
}

function Invoke-ParsecIngredientExecute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{}
    )

    return Invoke-ParsecIngredientOperation -Name $Name -Operation 'apply' -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState
}

function Invoke-ParsecIngredientVerify {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{}
    )

    $definition = Get-ParsecIngredientDefinition -Name $Name
    if (-not (Test-ParsecIngredientOperationSupported -Definition $definition -Operation 'verify')) {
        return $null
    }

    return Invoke-ParsecIngredientOperation -Name $Name -Operation 'verify' -Arguments $Arguments -ExecutionResult $ExecutionResult -StateRoot $StateRoot -RunState $RunState
}

function Invoke-ParsecIngredientCompensate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{}
    )

    $definition = Get-ParsecIngredientDefinition -Name $Name
    if (-not (Test-ParsecIngredientOperationSupported -Definition $definition -Operation 'reset')) {
        return $null
    }

    return Invoke-ParsecIngredientOperation -Name $Name -Operation 'reset' -Arguments $Arguments -ExecutionResult $ExecutionResult -StateRoot $StateRoot -RunState $RunState
}

function Get-ParsecIngredientModuleRoot {
    [CmdletBinding()]
    param()

    return Join-Path -Path $PSScriptRoot -ChildPath 'Ingredients'
}

function New-ParsecIngredientDefinitionFromSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Schema,

        [Parameter(Mandatory)]
        [hashtable] $Operations
    )

    $operationSchemas = [ordered]@{}
    if ($Schema.Contains('operation_schemas')) {
        foreach ($operationName in $Schema.operation_schemas.Keys) {
            $operationSchemas[$operationName] = ConvertTo-ParsecPlainObject -InputObject $Schema.operation_schemas[$operationName]
        }
    }

    $readiness = [ordered]@{}
    if ($Schema.Contains('readiness')) {
        $readiness = ConvertTo-ParsecPlainObject -InputObject $Schema.readiness
    }

    return New-ParsecIngredientDefinition `
        -Name ([string] $Schema.name) `
        -Kind ([string] $Schema.kind) `
        -Description ([string] $Schema.description) `
        -Aliases $(if ($Schema.Contains('aliases')) { @($Schema.aliases) } else { @() }) `
        -Capabilities @($Schema.capabilities) `
        -RequiredBackends @($Schema.required_backends) `
        -OperationSchemas $operationSchemas `
        -SafetyClass ([string] $Schema.safety_class) `
        -SuccessSignals @($Schema.success_signals) `
        -FailureSignals @($Schema.failure_signals) `
        -WaitConditions @($Schema.wait_conditions) `
        -Readiness $readiness `
        -Operations $Operations
}

function Import-ParsecIngredientModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $IngredientPath
    )

    $schemaPath = Join-Path -Path $IngredientPath -ChildPath 'schema.toml'
    $libraryPath = Join-Path -Path $IngredientPath -ChildPath 'lib.ps1'
    if (-not (Test-Path -LiteralPath $schemaPath) -or -not (Test-Path -LiteralPath $libraryPath)) {
        throw "Ingredient module '$IngredientPath' is missing schema.toml or lib.ps1."
    }

    $schema = ConvertFrom-ParsecToml -Path $schemaPath
    . $libraryPath
    try {
        $operations = Get-ParsecIngredientOperations
    }
    finally {
        if (Test-Path -LiteralPath Function:\Get-ParsecIngredientOperations) {
            Remove-Item -LiteralPath Function:\Get-ParsecIngredientOperations -Force
        }
    }

    Register-ParsecIngredient -Definition (New-ParsecIngredientDefinitionFromSchema -Schema $schema -Operations $operations) | Out-Null
}

function Initialize-ParsecIngredientRegistry {
    [CmdletBinding()]
    param()

    if ($script:ParsecIngredientRegistry.Count -gt 0) {
        return
    }

    $moduleRoot = Get-ParsecIngredientModuleRoot
    foreach ($directory in Get-ChildItem -LiteralPath $moduleRoot -Directory | Sort-Object Name) {
        Import-ParsecIngredientModule -IngredientPath $directory.FullName
    }
}
