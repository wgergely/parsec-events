using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace ParsecEventExecutor;

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
