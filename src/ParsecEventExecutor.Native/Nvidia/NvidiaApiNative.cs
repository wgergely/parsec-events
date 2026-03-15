using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

namespace ParsecEventExecutor;

[StructLayout(LayoutKind.Sequential, Pack = 8)]
internal struct NV_VIEWPORTF {
    public float x;
    public float y;
    public float w;
    public float h;
}

[StructLayout(LayoutKind.Sequential, Pack = 8)]
internal struct NV_TIMING_FLAG {
    public uint interlaceAndReserved;
    public uint formatId;
    public uint scaling;
}

[StructLayout(LayoutKind.Sequential, Pack = 8)]
internal struct NV_TIMINGEXT {
    public uint flag;
    public ushort rr;
    public uint rrx1k;
    public uint aspect;
    public ushort rep;
    public uint status;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 40)]
    public byte[] name;
}

[StructLayout(LayoutKind.Sequential, Pack = 8)]
internal struct NV_TIMING {
    public ushort HVisible;
    public ushort HBorder;
    public ushort HFrontPorch;
    public ushort HSyncWidth;
    public ushort HTotal;
    public byte HSyncPol;
    public ushort VVisible;
    public ushort VBorder;
    public ushort VFrontPorch;
    public ushort VSyncWidth;
    public ushort VTotal;
    public byte VSyncPol;
    public ushort interlaced;
    public uint pclk;
    public NV_TIMINGEXT etc;
}

[StructLayout(LayoutKind.Sequential, Pack = 8)]
internal struct NV_TIMING_INPUT {
    public uint version;
    public uint width;
    public uint height;
    public float rr;
    public NV_TIMING_FLAG flag;
    public int type;
}

[StructLayout(LayoutKind.Sequential, Pack = 8)]
internal struct NV_CUSTOM_DISPLAY {
    public uint version;
    public uint width;
    public uint height;
    public uint depth;
    public int colorFormat;
    public NV_VIEWPORTF srcPartition;
    public float xRatio;
    public float yRatio;
    public NV_TIMING timing;
    public uint hwModeSetOnly;
}

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate IntPtr NvapiQueryInterfaceDelegate(uint interfaceId);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate int NvapiInitializeDelegate();

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate int NvapiGetErrorMessageDelegate(int status, StringBuilder description);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate int NvapiGetDisplayIdByDisplayNameDelegate([MarshalAs(UnmanagedType.LPStr)] string displayName, out uint displayId);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate int NvapiGetTimingDelegate(uint displayId, ref NV_TIMING_INPUT timingInput, out NV_TIMING timing);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate int NvapiEnumCustomDisplayDelegate(uint displayId, uint index, ref NV_CUSTOM_DISPLAY customDisplay);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate int NvapiTryCustomDisplayDelegate([In] uint[] displayIds, uint count, [In, Out] NV_CUSTOM_DISPLAY[] customDisplays);

[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
internal delegate int NvapiSaveCustomDisplayDelegate([In] uint[] displayIds, uint count, uint isThisOutputIdOnly, uint isThisMonitorIdOnly);

public static class NvidiaApiNative {
    private const int NVAPI_OK = 0;
    private const int NVAPI_END_ENUMERATION = -7;
    private const int NV_FORMAT_UNKNOWN = 0;
    private const int NV_TIMING_OVERRIDE_AUTO = 1;
    private const uint NvAPI_Initialize_Id = 0x0150e828;
    private const uint NvAPI_GetErrorMessage_Id = 0x6c2d048c;
    private const uint NvAPI_DISP_GetTiming_Id = 0x175167e9;
    private const uint NvAPI_DISP_EnumCustomDisplay_Id = 0xa2072d59;
    private const uint NvAPI_DISP_TryCustomDisplay_Id = 0x1f7db630;
    private const uint NvAPI_DISP_SaveCustomDisplay_Id = 0x49882876;
    private const uint NvAPI_DISP_GetDisplayIdByDisplayName_Id = 0xae457190;

    private static readonly object SyncRoot = new object();
    private static IntPtr _libraryHandle = IntPtr.Zero;
    private static string _loadedLibraryPath;
    private static NvapiQueryInterfaceDelegate _queryInterface;
    private static NvapiInitializeDelegate _initialize;
    private static NvapiGetErrorMessageDelegate _getErrorMessage;
    private static NvapiGetDisplayIdByDisplayNameDelegate _getDisplayIdByDisplayName;
    private static NvapiGetTimingDelegate _getTiming;
    private static NvapiEnumCustomDisplayDelegate _enumCustomDisplay;
    private static NvapiTryCustomDisplayDelegate _tryCustomDisplay;
    private static NvapiSaveCustomDisplayDelegate _saveCustomDisplay;
    private static bool _initialized;

    [DllImport("kernel32", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryW(string fileName);

    [DllImport("kernel32", CharSet = CharSet.Ansi, ExactSpelling = true, SetLastError = true)]
    private static extern IntPtr GetProcAddress(IntPtr module, string procName);

    private static uint MakeVersion(Type type, uint version) {
        return (uint)(Marshal.SizeOf(type) | ((int)version << 16));
    }

    private static TDelegate ResolveDelegate<TDelegate>(uint interfaceId) where TDelegate : class {
        IntPtr pointer = _queryInterface(interfaceId);
        if (pointer == IntPtr.Zero) {
            throw new InvalidOperationException(string.Format("NVAPI interface 0x{0:x8} is not available.", interfaceId));
        }

        return Marshal.GetDelegateForFunctionPointer(pointer, typeof(TDelegate)) as TDelegate;
    }

    private static void EnsureLoaded(string libraryPath) {
        lock (SyncRoot) {
            if (_libraryHandle != IntPtr.Zero) {
                if (!string.Equals(_loadedLibraryPath, libraryPath, StringComparison.OrdinalIgnoreCase)) {
                    throw new InvalidOperationException(string.Format("NVAPI is already loaded from '{0}', not '{1}'.", _loadedLibraryPath, libraryPath));
                }

                return;
            }

            _libraryHandle = LoadLibraryW(libraryPath);
            if (_libraryHandle == IntPtr.Zero) {
                throw new Win32Exception(Marshal.GetLastWin32Error(), string.Format("Failed to load NVAPI library '{0}'.", libraryPath));
            }

            IntPtr queryPointer = GetProcAddress(_libraryHandle, "nvapi_QueryInterface");
            if (queryPointer == IntPtr.Zero) {
                throw new Win32Exception(Marshal.GetLastWin32Error(), "NVAPI library does not export nvapi_QueryInterface.");
            }

            _loadedLibraryPath = libraryPath;
            _queryInterface = Marshal.GetDelegateForFunctionPointer(queryPointer, typeof(NvapiQueryInterfaceDelegate)) as NvapiQueryInterfaceDelegate;
            _initialize = ResolveDelegate<NvapiInitializeDelegate>(NvAPI_Initialize_Id);
            _getErrorMessage = ResolveDelegate<NvapiGetErrorMessageDelegate>(NvAPI_GetErrorMessage_Id);
            _getDisplayIdByDisplayName = ResolveDelegate<NvapiGetDisplayIdByDisplayNameDelegate>(NvAPI_DISP_GetDisplayIdByDisplayName_Id);
            _getTiming = ResolveDelegate<NvapiGetTimingDelegate>(NvAPI_DISP_GetTiming_Id);
            _enumCustomDisplay = ResolveDelegate<NvapiEnumCustomDisplayDelegate>(NvAPI_DISP_EnumCustomDisplay_Id);
            _tryCustomDisplay = ResolveDelegate<NvapiTryCustomDisplayDelegate>(NvAPI_DISP_TryCustomDisplay_Id);
            _saveCustomDisplay = ResolveDelegate<NvapiSaveCustomDisplayDelegate>(NvAPI_DISP_SaveCustomDisplay_Id);
        }
    }

    public static void EnsureInitialized(string libraryPath) {
        EnsureLoaded(libraryPath);
        lock (SyncRoot) {
            if (_initialized) {
                return;
            }

            int status = _initialize();
            if (status != NVAPI_OK) {
                throw new InvalidOperationException(string.Format("NvAPI_Initialize failed: {0}", GetErrorMessage(libraryPath, status)));
            }

            _initialized = true;
        }
    }

    public static string GetErrorMessage(string libraryPath, int status) {
        EnsureLoaded(libraryPath);
        StringBuilder description = new StringBuilder(64);
        int errorStatus = _getErrorMessage(status, description);
        if (errorStatus != NVAPI_OK || description.Length == 0) {
            return string.Format("NVAPI status {0}", status);
        }

        return description.ToString();
    }

    private static NV_CUSTOM_DISPLAY CreateCustomDisplay() {
        return new NV_CUSTOM_DISPLAY {
            version = MakeVersion(typeof(NV_CUSTOM_DISPLAY), 1),
            depth = 32,
            colorFormat = NV_FORMAT_UNKNOWN,
            srcPartition = new NV_VIEWPORTF { x = 0.0f, y = 0.0f, w = 1.0f, h = 1.0f },
            xRatio = 1.0f,
            yRatio = 1.0f,
            hwModeSetOnly = 0,
            timing = new NV_TIMING {
                etc = new NV_TIMINGEXT {
                    name = new byte[40]
                }
            }
        };
    }

    private static NvidiaCustomDisplayRecord ToRecord(NV_CUSTOM_DISPLAY customDisplay) {
        float refreshRate = 0.0f;
        if (customDisplay.timing.etc.rrx1k > 0) {
            refreshRate = customDisplay.timing.etc.rrx1k / 1000.0f;
        }
        else if (customDisplay.timing.etc.rr > 0) {
            refreshRate = customDisplay.timing.etc.rr;
        }

        return new NvidiaCustomDisplayRecord {
            Width = customDisplay.width,
            Height = customDisplay.height,
            Depth = customDisplay.depth,
            ColorFormat = customDisplay.colorFormat,
            RefreshRateHz = refreshRate,
            TimingStatus = customDisplay.timing.etc.status,
            HardwareModeSetOnly = customDisplay.hwModeSetOnly != 0
        };
    }

    public static uint GetDisplayIdByDisplayName(string libraryPath, string displayName) {
        EnsureInitialized(libraryPath);
        uint displayId;
        int status = _getDisplayIdByDisplayName(displayName, out displayId);
        if (status != NVAPI_OK) {
            throw new InvalidOperationException(string.Format("NvAPI_DISP_GetDisplayIdByDisplayName('{0}') failed: {1}", displayName, GetErrorMessage(libraryPath, status)));
        }

        return displayId;
    }

    public static NvidiaCustomDisplayRecord[] EnumCustomDisplays(string libraryPath, uint displayId) {
        EnsureInitialized(libraryPath);
        List<NvidiaCustomDisplayRecord> displays = new List<NvidiaCustomDisplayRecord>();
        uint index = 0;
        while (true) {
            NV_CUSTOM_DISPLAY customDisplay = CreateCustomDisplay();
            int status = _enumCustomDisplay(displayId, index, ref customDisplay);
            if (status == NVAPI_END_ENUMERATION) {
                break;
            }

            if (status != NVAPI_OK) {
                throw new InvalidOperationException(string.Format("NvAPI_DISP_EnumCustomDisplay(displayId={0}, index={1}) failed: {2}", displayId, index, GetErrorMessage(libraryPath, status)));
            }

            displays.Add(ToRecord(customDisplay));
            index++;
        }

        return displays.ToArray();
    }

    public static NvidiaCustomDisplayRecord TryAndSaveCustomDisplay(string libraryPath, uint displayId, uint width, uint height, float refreshRateHz, uint depth) {
        EnsureInitialized(libraryPath);

        NV_TIMING_INPUT timingInput = new NV_TIMING_INPUT {
            version = MakeVersion(typeof(NV_TIMING_INPUT), 1),
            width = width,
            height = height,
            rr = refreshRateHz,
            flag = new NV_TIMING_FLAG(),
            type = NV_TIMING_OVERRIDE_AUTO
        };

        NV_TIMING timing;
        int timingStatus = _getTiming(displayId, ref timingInput, out timing);
        if (timingStatus != NVAPI_OK) {
            throw new InvalidOperationException(string.Format("NvAPI_DISP_GetTiming(displayId={0}, {1}x{2}@{3:0.###}) failed: {4}", displayId, width, height, refreshRateHz, GetErrorMessage(libraryPath, timingStatus)));
        }

        NV_CUSTOM_DISPLAY customDisplay = CreateCustomDisplay();
        customDisplay.width = width;
        customDisplay.height = height;
        customDisplay.depth = depth;
        customDisplay.timing = timing;

        uint[] displayIds = new uint[] { displayId };
        NV_CUSTOM_DISPLAY[] displays = new NV_CUSTOM_DISPLAY[] { customDisplay };

        int tryStatus = _tryCustomDisplay(displayIds, 1, displays);
        if (tryStatus != NVAPI_OK) {
            throw new InvalidOperationException(string.Format("NvAPI_DISP_TryCustomDisplay(displayId={0}, {1}x{2}@{3:0.###}) failed: {4}", displayId, width, height, refreshRateHz, GetErrorMessage(libraryPath, tryStatus)));
        }

        int saveStatus = _saveCustomDisplay(displayIds, 1, 1, 1);
        if (saveStatus != NVAPI_OK) {
            throw new InvalidOperationException(string.Format("NvAPI_DISP_SaveCustomDisplay(displayId={0}, {1}x{2}@{3:0.###}) failed: {4}", displayId, width, height, refreshRateHz, GetErrorMessage(libraryPath, saveStatus)));
        }

        return ToRecord(displays[0]);
    }
}
