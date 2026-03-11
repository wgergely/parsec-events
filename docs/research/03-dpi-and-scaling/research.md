# DPI and Scaling: UI Scaling, Text Scaling, and Apply Strategies

## Status: Viable but Complex — Shell Restart Likely Required

## Problem Statement

The mobile mode requires UI scaling at 300% and text scaling at 130%. The desktop mode uses the monitors' native scaling (typically 100–150% depending on panel). Unlike resolution and orientation changes, DPI and scaling changes in Windows are deeply entangled with the shell (explorer.exe) and running applications. Changing these values programmatically is straightforward; *applying* them without a full logoff is the hard problem.

## Research Findings

### UI Scaling (DPI Override)

#### Registry Location

Per-monitor DPI scaling is stored at:

```
HKCU\Control Panel\Desktop\PerMonitorSettings\<MonitorID>\DpiValue
```

A system-wide fallback exists at:

```
HKLM\System\CurrentControlSet\Control\GraphicsDrivers\ScaleFactors\<MonitorID>
```

The `<MonitorID>` is a hardware-derived string (e.g., a PnP device path). When the monitor topology changes (as in our multi-to-single switch), the ID that Windows assigns to the remaining active monitor must be known.

#### DpiValue Encoding

The `DpiValue` DWORD encodes the scaling percentage, but not as a direct percentage:

| DpiValue | Meaning (external monitors) | Meaning (laptop panels) |
|---|---|---|
| 0 | 100% (default) | Panel's recommended scaling |
| 1 | 125% | +25% from recommended |
| 2 | 150% | +50% from recommended |
| 3 | 175% | +75% from recommended |
| FFFFFFFE (-2) | -50% from recommended | 100% on a HiDPI panel |
| FFFFFFFF (-1) | -25% from recommended | 125% on a HiDPI panel |

The encoding is relative and differs between external monitors and built-in laptop panels. For a 300% target, the exact DpiValue depends on the monitor's default scaling — this must be determined empirically on the target hardware.

**Reference**: [Windows 10 DPI Scaling Forums](https://www.tenforums.com/tutorials/5990-change-dpi-scaling-level-displays-windows-10-a-6.html), [Windows 11 DPI Scaling](https://www.elevenforum.com/t/change-display-dpi-scaling-level-in-windows-11.934/)

#### Applying DPI Changes Without Logoff

This is the single hardest technical challenge in the project. Findings:

1. **Registry-only change**: Writing to `PerMonitorSettings` does NOT take effect until the user logs off and back on, or at minimum until `explorer.exe` restarts. Applications cache their DPI awareness at startup and do not re-query.

2. **Explorer restart**: Killing and restarting `explorer.exe` forces the shell (taskbar, desktop, Start menu) to re-read scaling. This is the most common workaround used by community tools. However, other running applications (non-UWP) will not pick up the new DPI — they continue at their startup DPI until individually restarted.

3. **SetProcessDpiAwarenessContext**: This Win32 API allows a process to declare its DPI awareness, but it can only be called by the process itself — one process cannot force another to change its DPI context.

4. **WM_DPICHANGED**: Windows sends this message to top-level windows when their DPI changes (e.g., when dragged between monitors with different scaling). However, this is not broadcast globally on a scaling settings change — it is per-window, per-monitor.

5. **SystemParametersInfo with SPI_SETLOGICALDPIOVERRIDE**: This undocumented call has been reported to apply DPI changes more aggressively, but it is version-dependent and not guaranteed across Windows updates.

**Architecture implication**: For the Parsec use case, explorer restart is likely acceptable because the transition happens at the moment of remote connection — no user is sitting in front of the physical screens. The remote Parsec client will reconnect to the new desktop state. Applications that were running will display at stale DPI, but since the user is operating remotely at the target scaling, this may be acceptable for most workflows.

### Text Scaling (Accessibility Setting)

#### Registry Location

```
HKCU\SOFTWARE\Microsoft\Accessibility\TextScaleFactor
```

This is a DWORD value representing a percentage (100–225). The target mobile mode requires 130.

#### Applying Text Scaling Changes

Text scaling affects UWP/modern apps and some system UI elements. Findings:

1. **Registry change alone is insufficient**: Setting the value does not trigger an immediate UI update. The system must be notified that the setting changed.

2. **Event-driven notification**: Windows exposes a `TextScaleFactorChanged` event via the `UISettings` class (WinRT). The `TextScaleFactor` property is a double in the range [1.0, 2.25]. Applications that listen for this event will update live. However, *triggering* this event from outside the Settings app is not straightforward.

3. **Desktop vs. UWP scope**: The `TextScaleFactor` key primarily affects Universal/UWP apps. Classic Win32 desktop apps instead read font metrics from `HKCU\Control Panel\Desktop\WindowMetrics`. Changing text scaling for desktop apps requires modifying `WindowMetrics` values and broadcasting `WM_SETTINGCHANGE`.

4. **Broadcasting WM_SETTINGCHANGE**: After modifying the registry, calling `SendMessageTimeout` with `HWND_BROADCAST` and `WM_SETTINGCHANGE` (with lParam pointing to the string "WindowMetrics") can nudge some applications to re-read settings. This is not guaranteed to work for all applications.

**Reference**: [Microsoft Q&A: TextScaleFactor registry](https://learn.microsoft.com/en-us/answers/questions/520262/registry-key-to-get-windows-text-scale-factor-valu), [Microsoft: Accessible text requirements](https://learn.microsoft.com/en-us/windows/apps/design/accessibility/accessible-text-requirements)

### Relationship Between CCD API Scaling and DPI Scaling

The CCD API (`SetDisplayConfig`) has its own notion of scaling — this controls how the GPU scales the rendered image to the physical panel (e.g., centered, stretched, aspect-ratio preserved). This is *not* the same as Windows DPI scaling. They are orthogonal:

- **CCD scaling**: GPU-level image scaling to fit panel resolution. Controlled via `SetDisplayConfig`.
- **DPI scaling**: OS-level UI element sizing. Controlled via registry + shell restart.

Both must be set correctly for the mobile mode to work, but they are configured through entirely different mechanisms.

## Open Questions Requiring Empirical Validation

1. **Explorer restart during Parsec session**: Does killing `explorer.exe` during an active Parsec session disrupt the remote connection? Parsec hooks into the display at a lower level than the shell, so it should survive, but this must be confirmed.

2. **DpiValue for 300% on target hardware**: What `DpiValue` DWORD corresponds to 300% scaling on the specific monitor being used? This depends on the monitor's native DPI and Windows' default recommendation.

3. **TextScaleFactor broadcast effectiveness**: Does broadcasting `WM_SETTINGCHANGE` after setting `TextScaleFactor` actually cause visible UI updates in the apps typically used during remote sessions?

4. **Ordering dependency**: Must DPI changes be applied before or after the resolution/orientation change? Or is the order irrelevant?

## Architecture Decision Required

**Decision**: Apply DPI and text scaling via registry writes, followed by an `explorer.exe` restart. Accept that non-UWP applications already running will retain their pre-change DPI until individually restarted.

**Rationale**: There is no clean, universal mechanism to force all running applications to adopt new DPI scaling. The explorer restart is the pragmatic middle ground — it updates the shell and any newly launched applications. Since the transition coincides with a Parsec connect/disconnect event (where the user is switching usage modes anyway), the partial-update behavior is acceptable.

**Fallback consideration**: If explorer restart proves disruptive to the Parsec session, an alternative is to apply DPI changes *and then* prompt the Parsec client to reconnect (effectively a soft session restart). This needs empirical testing.

## References

- [Microsoft: DPI-related APIs and registry settings](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dpi-related-apis-and-registry-settings)
- [Windows 11 Forum: Change Display DPI Scaling](https://www.elevenforum.com/t/change-display-dpi-scaling-level-in-windows-11.934/)
- [Windows 10 Forums: DPI Scaling Level](https://www.tenforums.com/tutorials/5990-change-dpi-scaling-level-displays-windows-10-a-6.html)
- [AutoHotkey Forums: PerMonitorSettings and scaling detection](https://www.autohotkey.com/boards/viewtopic.php?t=34701)
- [Microsoft Q&A: Command line for scaling](https://learn.microsoft.com/en-us/answers/questions/65033/command-line-for-scaling-in-windows-settings-for-d)
- [Microsoft Q&A: .NET API for accessibility settings](https://learn.microsoft.com/en-us/answers/questions/869360/any-net-api-available-to-change-the-accessibility)
