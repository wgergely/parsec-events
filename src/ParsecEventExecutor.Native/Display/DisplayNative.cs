using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace ParsecEventExecutor;

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
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

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

    private const int SW_RESTORE = 9;

    private static bool ForceSetForegroundWindow(IntPtr hWnd) {
        var foreground = GetForegroundWindow();
        if (foreground == hWnd) {
            return true;
        }

        uint currentThreadId = GetCurrentThreadId();
        uint foregroundThreadId = 0;
        if (foreground != IntPtr.Zero) {
            foregroundThreadId = GetWindowThreadProcessId(foreground, out _);
        }
        uint targetThreadId = GetWindowThreadProcessId(hWnd, out _);

        bool attached = false;
        try {
            if (foregroundThreadId != 0 && foregroundThreadId != currentThreadId) {
                attached = AttachThreadInput(currentThreadId, foregroundThreadId, true);
            }

            BringWindowToTop(hWnd);
            SetForegroundWindow(hWnd);
        }
        finally {
            if (attached) {
                AttachThreadInput(currentThreadId, foregroundThreadId, false);
            }
        }

        return GetForegroundWindow() == hWnd;
    }

    public static bool StepAltTab() {
        // Find the next eligible alt-tab window after the current foreground
        var foreground = GetForegroundWindow();
        if (foreground == IntPtr.Zero) {
            return false;
        }

        var windows = GetTopLevelWindows();
        IntPtr nextWindow = IntPtr.Zero;
        bool passedForeground = false;

        foreach (var w in windows) {
            var wHandle = new IntPtr(w.Handle);
            if (wHandle == foreground) {
                passedForeground = true;
                continue;
            }

            if (!passedForeground) {
                continue;
            }

            // Alt-tab criteria: visible, not cloaked, not tool window, has title, no owner
            if (w.IsVisible && !w.IsCloaked && !w.IsShellWindow &&
                !string.IsNullOrEmpty(w.Title) && w.OwnerHandle == 0 &&
                (w.ExtendedStyle & 0x00000080L) == 0) {
                nextWindow = wHandle;
                break;
            }
        }

        if (nextWindow == IntPtr.Zero) {
            return false;
        }

        if (IsIconic(nextWindow)) {
            ShowWindow(nextWindow, SW_RESTORE);
        }

        return ForceSetForegroundWindow(nextWindow);
    }

    public static bool ActivateWindow(long handle, bool restoreIfMinimized) {
        var hWnd = new IntPtr(handle);
        if (!IsWindow(hWnd)) {
            return false;
        }

        if (restoreIfMinimized && IsIconic(hWnd)) {
            ShowWindow(hWnd, SW_RESTORE);
        }

        return ForceSetForegroundWindow(hWnd);
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
