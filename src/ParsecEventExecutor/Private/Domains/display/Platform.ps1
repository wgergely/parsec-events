function Initialize-ParsecDisplayInterop {
    [CmdletBinding()]
    [OutputType([void])]
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
        public bool IsOnInputDesktop { get; set; }
        public bool IsOnCurrentVirtualDesktop { get; set; }
        public long ExtendedStyle { get; set; }
        public int Width { get; set; }
        public int Height { get; set; }
    }

    [ComImport]
    [Guid("A5CD92FF-29BE-454C-8D04-D82879FB3F1B")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IVirtualDesktopManager {
        [PreserveSig]
        int IsWindowOnCurrentVirtualDesktop(IntPtr topLevelWindow, out bool onCurrentDesktop);

        [PreserveSig]
        int GetWindowDesktopId(IntPtr topLevelWindow, out Guid desktopId);

        [PreserveSig]
        int MoveWindowToDesktop(IntPtr topLevelWindow, [MarshalAs(UnmanagedType.LPStruct)] Guid desktopId);
    }

    public static class DisplayNative {
        private const uint DESKTOP_READOBJECTS = 0x0001;
        private const uint DESKTOP_ENUMERATE = 0x0040;
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
        private static readonly Guid CLSID_VirtualDesktopManager = new Guid("AA509086-5CA9-4C25-8F95-589D3C07B48A");
        private static readonly IVirtualDesktopManager VirtualDesktopManager = CreateVirtualDesktopManager();
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

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr OpenInputDesktop(uint dwFlags, bool fInherit, uint dwDesiredAccess);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool CloseDesktop(IntPtr hDesktop);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool EnumDesktopWindows(IntPtr hDesktop, EnumWindowsProc lpfn, IntPtr lParam);

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

        private static IVirtualDesktopManager CreateVirtualDesktopManager() {
            try {
                return (IVirtualDesktopManager)Activator.CreateInstance(Type.GetTypeFromCLSID(CLSID_VirtualDesktopManager));
            }
            catch {
                return null;
            }
        }

        private static bool IsWindowOnCurrentVirtualDesktop(IntPtr hWnd) {
            if (VirtualDesktopManager == null || hWnd == IntPtr.Zero) {
                return true;
            }

            try {
                bool onCurrentDesktop;
                return VirtualDesktopManager.IsWindowOnCurrentVirtualDesktop(hWnd, out onCurrentDesktop) == 0 ? onCurrentDesktop : true;
            }
            catch {
                return true;
            }
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
                IsOnInputDesktop = true,
                IsOnCurrentVirtualDesktop = IsWindowOnCurrentVirtualDesktop(hWnd),
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
            var inputDesktop = OpenInputDesktop(0u, false, DESKTOP_READOBJECTS | DESKTOP_ENUMERATE);
            if (inputDesktop != IntPtr.Zero) {
                try {
                    EnumDesktopWindows(inputDesktop, delegate (IntPtr hWnd, IntPtr lParam) {
                        var capture = CaptureWindow(hWnd);
                        if (capture != null) {
                            windows.Add(capture);
                        }

                        return true;
                    }, IntPtr.Zero);
                }
                finally {
                    CloseDesktop(inputDesktop);
                }
            }
            else {
                EnumWindows(delegate (IntPtr hWnd, IntPtr lParam) {
                    var capture = CaptureWindow(hWnd);
                    if (capture != null) {
                        windows.Add(capture);
                    }

                    return true;
                }, IntPtr.Zero);
            }

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

        public static DEVMODE CreatePositionOnlyDevMode(int x, int y) {
            var mode = new DEVMODE();
            mode.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
            mode.dmFields = DM_POSITION;
            mode.dmPositionX = x;
            mode.dmPositionY = y;
            return mode;
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
            return $false
        }
    }

    $commitResult = [ParsecEventExecutor.DisplayNative]::ApplyPendingDisplayChanges()
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
    $mode.dmFields = $mode.dmFields -bor [ParsecEventExecutor.DisplayNative]::DM_PELSWIDTH -bor [ParsecEventExecutor.DisplayNative]::DM_PELSHEIGHT

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
            if ($null -ne $savedPos) {
                $otherMode.dmPositionX = [int] $savedPos.x
                $otherMode.dmPositionY = [int] $savedPos.y
            }
            else {
                $otherMode.dmPositionX = [int] $targetMonitor.bounds.width
                $otherMode.dmPositionY = 0
            }
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

