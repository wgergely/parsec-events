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

    public static class DisplayNative {
        private const int ENUM_CURRENT_SETTINGS = -1;
        private const int ENUM_REGISTRY_SETTINGS = -2;
        private const int MDT_EFFECTIVE_DPI = 0;
        private const int CCHDEVICENAME = 32;
        private const int CCHFORMNAME = 32;
        private const uint QDC_ALL_PATHS = 0x00000001;
        private const uint QDC_VIRTUAL_MODE_AWARE = 0x00000010;
        private const uint QDC_VIRTUAL_REFRESH_RATE_AWARE = 0x00000040;
        private const uint DISPLAYCONFIG_PATH_ACTIVE = 0x00000001;
        private const uint DISPLAYCONFIG_MODE_INFO_TYPE_SOURCE = 1;
        private const uint DISPLAYCONFIG_MODE_INFO_TYPE_TARGET = 2;
        private const uint DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME = 1;
        private const uint DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME = 2;
        private const uint DISPLAYCONFIG_DEVICE_INFO_GET_ADAPTER_NAME = 4;
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

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
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
        private static extern IntPtr SendNotifyMessage(IntPtr hWnd, uint Msg, IntPtr wParam, string lParam);

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

        private static string AdapterIdToString(LUID value) {
            return value.HighPart.ToString("X8") + ":" + value.LowPart.ToString("X8");
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

        private static void ThrowIfWin32Error(int errorCode, string apiName) {
            if (errorCode != 0) {
                throw new Win32Exception(errorCode, apiName + " failed.");
            }
        }

        public static void BroadcastSettingChange(string area) {
            SendNotifyMessage(new IntPtr(0xffff), 0x001A, IntPtr.Zero, area);
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
    param()

    $path = 'HKCU:\Control Panel\Desktop'
    $logPixels = 96

    try {
        $value = Get-ItemPropertyValue -Path $path -Name 'LogPixels' -ErrorAction Stop
        if ($value -is [int] -and $value -gt 0) {
            $logPixels = [int] $value
        }
    }
    catch {
        Write-Verbose 'LogPixels could not be read from the registry. Falling back to 100%.'
    }

    return [int] [Math]::Round(($logPixels * 100.0) / 96.0)
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
        return New-ParsecDisplayChangeFailureResult -Action "$Action:test" -Code $testResult -Requested $Requested
    }

    $stageFlags = [ParsecEventExecutor.DisplayNative]::CDS_UPDATEREGISTRY -bor [ParsecEventExecutor.DisplayNative]::CDS_NORESET -bor $Flags
    $stageResult = [ParsecEventExecutor.DisplayNative]::ApplyDeviceMode($DeviceName, $Mode, [uint32] $stageFlags)
    if ($stageResult -ne [ParsecEventExecutor.DisplayNative]::DISP_CHANGE_SUCCESSFUL) {
        return New-ParsecDisplayChangeFailureResult -Action "$Action:stage" -Code $stageResult -Requested $Requested
    }

    $commitResult = [ParsecEventExecutor.DisplayNative]::ApplyPendingDisplayChanges()
    if ($commitResult -ne [ParsecEventExecutor.DisplayNative]::DISP_CHANGE_SUCCESSFUL) {
        return New-ParsecDisplayChangeFailureResult -Action "$Action:commit" -Code $commitResult -Requested $Requested
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

    $result = Invoke-ParsecApplyDisplayMode -DeviceName $deviceName -Mode $mode -Flags [ParsecEventExecutor.DisplayNative]::CDS_SET_PRIMARY -Action 'SetPrimary' -Requested $Arguments
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

    $scalePercent = if ($Arguments.ContainsKey('scale_percent')) {
        [int] $Arguments.scale_percent
    }
    elseif ($Arguments.ContainsKey('value')) {
        [int] $Arguments.value
    }
    elseif ($Arguments.ContainsKey('captured_state') -and $Arguments.captured_state -is [System.Collections.IDictionary] -and $Arguments.captured_state.Contains('ui_scale_percent')) {
        [int] $Arguments.captured_state.ui_scale_percent
    }
    else {
        throw 'UI scaling apply requires scale_percent or value.'
    }

    if ($scalePercent -lt 100 -or $scalePercent -gt 500) {
        throw 'UI scaling percent must be between 100 and 500.'
    }

    $path = 'HKCU:\Control Panel\Desktop'
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -Path $path -Force | Out-Null
    }

    $logPixels = ConvertTo-ParsecLogPixels -ScalePercent $scalePercent
    $win8Scaling = if ($scalePercent -eq 100) { 0 } else { 1 }

    New-ItemProperty -Path $path -Name 'LogPixels' -Value $logPixels -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $path -Name 'Win8DpiScaling' -Value $win8Scaling -PropertyType DWord -Force | Out-Null
    Initialize-ParsecPersonalizationInterop
    [ParsecEventExecutor.DisplayNative]::BroadcastSettingChange('WindowMetrics')
    [ParsecEventExecutor.DisplayNative]::BroadcastSettingChange('Environment')

    return New-ParsecResult -Status 'Succeeded' -Message "UI scaling requested at $scalePercent%." -Observed @{
        ui_scale_percent = $scalePercent
        log_pixels = $logPixels
        requires_signout = $true
    } -Outputs @{
        ui_scale_percent = $scalePercent
        log_pixels = $logPixels
        requires_signout = $true
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
        SetThemeState = {
            param([hashtable] $Arguments)
            return Set-ParsecThemeStateInternal -Arguments $Arguments
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
            $scalePercent = if ($null -ne $nativeMonitor -and $nativeMonitor.HasEffectiveDpi) { Get-ParsecScalePercent -EffectiveDpiX $nativeMonitor.EffectiveDpiX } else { $null }
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
        }
    }
    catch {
        Add-Type -AssemblyName System.Windows.Forms
        $screens = [System.Windows.Forms.Screen]::AllScreens
        $textScalePercent = Get-ParsecTextScalePercent
        $uiScalePercent = Get-ParsecUiScalePercent
        $themeState = Invoke-ParsecPersonalizationAdapter -Method 'GetThemeState'
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

    $actions = New-Object System.Collections.Generic.List[object]
    foreach ($monitor in @($SnapshotDocument.display.monitors)) {
        if ($monitor.Contains('enabled')) {
            $actions.Add((Invoke-ParsecDisplayAdapter -Method 'SetEnabled' -Arguments @{ device_name = $monitor.device_name; enabled = [bool] $monitor.enabled }))
        }
    }

    foreach ($monitor in @($SnapshotDocument.display.monitors)) {
        if ($monitor.Contains('bounds')) {
            $actions.Add((Invoke-ParsecDisplayAdapter -Method 'SetResolution' -Arguments @{ device_name = $monitor.device_name; width = [int] $monitor.bounds.width; height = [int] $monitor.bounds.height }))
        }
    }

    foreach ($monitor in @($SnapshotDocument.display.monitors)) {
        if ($monitor.Contains('orientation') -and $monitor.orientation -ne 'Unknown') {
            $actions.Add((Invoke-ParsecDisplayAdapter -Method 'SetOrientation' -Arguments @{ device_name = $monitor.device_name; orientation = $monitor.orientation }))
        }
    }

    foreach ($monitor in @($SnapshotDocument.display.monitors)) {
        if ($monitor.Contains('is_primary') -and [bool] $monitor.is_primary) {
            $actions.Add((Invoke-ParsecDisplayAdapter -Method 'SetPrimary' -Arguments @{ device_name = $monitor.device_name }))
        }
    }

    if ($SnapshotDocument.display.Contains('font_scaling') -and $SnapshotDocument.display.font_scaling.Contains('text_scale_percent')) {
        $actions.Add((Invoke-ParsecDisplayAdapter -Method 'SetScaling' -Arguments @{ text_scale_percent = [int] $SnapshotDocument.display.font_scaling.text_scale_percent }))
    }

    if ($SnapshotDocument.display.Contains('theme')) {
        $actions.Add((Invoke-ParsecPersonalizationAdapter -Method 'SetThemeState' -Arguments @{ theme_state = $SnapshotDocument.display.theme }))
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
