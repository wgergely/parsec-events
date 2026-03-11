# Display Configuration: Resolution, Orientation, and Topology

## Status: Viable — Two API Generations Available, Decision Required

## Problem Statement

When switching to "mobile mode," the host machine must transition from a multi-monitor setup (two or three screens at native resolution, landscape orientation) to a single-monitor configuration at 2000x3000 in portrait orientation. The reverse transition must restore the original multi-monitor layout. These changes must be applied programmatically, immediately, and without user interaction.

## Research Findings

### Win32 API Surface: Two Generations

Windows exposes two distinct APIs for display configuration, and the choice between them is a foundational architecture decision.

#### Legacy API: ChangeDisplaySettingsEx

The older API operates through the `DEVMODE` structure, which conflates source mode (what the OS renders) and target mode (what the monitor displays) into a single data blob.

Key characteristics:
- Requires P/Invoke from PowerShell (inline C# defining the DEVMODE struct and the API signature).
- Orientation is controlled via `dmDisplayOrientation` in the DEVMODE struct: 0 = landscape, 1 = portrait (rotated 90°), 2 = landscape flipped, 3 = portrait flipped.
- Multi-monitor changes require calling `ChangeDisplaySettingsEx` once per display, then a final "commit" call with NULL parameters.
- Some graphics drivers do not support programmatic rotation through this API; NVIDIA and AMD control panels sometimes use undocumented private interfaces instead.

**Reference**: [Microsoft ChangeDisplaySettingsEx documentation](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-changedisplaysettingsexa)

#### Modern API: CCD (Connecting and Configuring Displays) / SetDisplayConfig

The newer CCD API (Windows 7+) explicitly separates source and target mode information and provides richer control over display topology.

Key characteristics:
- Uses `QueryDisplayConfig` to read current state, `SetDisplayConfig` to apply changes.
- Topology, layout, orientation, scaling, bit depth, and refresh rate are all addressable independently.
- Scaling is expressed as *intent* rather than absolute value — the API negotiates with the driver.
- Designed for multi-monitor scenarios from the ground up.
- Microsoft explicitly states the legacy `ChangeDisplaySettings` API is deprecated for new development.

**Reference**: [Microsoft SetDisplayConfig documentation](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setdisplayconfig), [SetDisplayConfig Summary and Scenarios](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/setdisplayconfig-summary-and-scenarios)

#### PowerShell Module: DisplayConfig

The [DisplayConfig](https://github.com/MartinGC94/DisplayConfig) PowerShell module wraps the CCD APIs in a PowerShell-native interface. It is 97.5% C# (compiled P/Invoke layer) with a thin PowerShell cmdlet surface.

Capabilities:
- Set resolution, refresh rate, scaling, and desktop position.
- Aggregate multiple settings changes into a single atomic apply (reducing flicker).
- Export full display configurations to XML via `Export-Clixml`.
- Restore saved configurations, including adapter ID remapping for hardware changes.

This module is the strongest candidate for the implementation layer, as it abstracts the CCD API complexity while preserving full control.

#### Command-Line Tool: MultiMonitorTool (NirSoft)

[MultiMonitorTool](https://www.nirsoft.net/utils/multi_monitor_tool.html) is a standalone utility from NirSoft that provides display configuration via command-line switches.

Key operations:
- `/SaveConfig "profile.cfg"` — exports the full monitor topology, resolution, position, and orientation.
- `/LoadConfig "profile.cfg"` — restores a saved configuration.
- `/SetMonitors` — applies settings to multiple monitors in a single call without a config file.

This is a simpler but less granular alternative to the DisplayConfig module. It trades programmability for ease of use — good for a "save known-good state, restore later" workflow.

**Reference**: [MultiMonitorTool homepage](https://www.nirsoft.net/utils/multi_monitor_tool.html), [GitHub usage examples](https://github.com/danielleevandenbosch/MultiMonitorTool)

### Orientation-Specific Considerations

The target setup requires portrait mode (90° rotation). Key findings:

- Both API generations support orientation changes, but driver support is not universal. Most modern NVIDIA and Intel drivers handle it correctly; some edge cases exist with AMD on specific panel types.
- When changing orientation, the resolution dimensions must be swapped in the API call (width and height invert). Some wrappers handle this automatically; raw API calls require the caller to manage it.
- Orientation changes via the API are applied immediately — no logoff or explorer restart required.

### Topology Changes: Disabling/Enabling Monitors

Switching from multi-monitor to single-monitor requires either disabling the extra displays or cloning. The CCD API supports this natively via topology flags (internal, external, clone, extend). The legacy API requires setting `CDS_SET_PRIMARY` and detaching secondary monitors individually.

**Architecture note**: Parsec's own display handling may fight with programmatic topology changes if Parsec is configured to auto-match the client's resolution. This interaction needs empirical testing — the automation script may need to run *after* Parsec completes its own display negotiation, which implies a short delay in the event handler.

## Open Questions Requiring Empirical Validation

1. **Parsec display negotiation timing**: When Parsec connects, does it modify the display configuration itself before the automation script runs? If so, what is the sequencing, and does the script need to wait for Parsec to finish?

2. **Driver compatibility**: Does the specific GPU on the host machine support programmatic portrait rotation via the CCD API? This must be tested on the actual hardware.

3. **Monitor identity stability**: When switching from three monitors to one, do Windows monitor IDs remain stable across transitions? If not, the restore path needs to identify monitors by hardware descriptor rather than ordinal ID.

4. **Display blanking duration**: How long does the screen go black during a topology change? This affects UX during the remote session.

## Architecture Decision Required

**Decision**: Use the CCD API (via the DisplayConfig PowerShell module) as the primary mechanism, with MultiMonitorTool as a fallback for profile save/restore if the module proves insufficient.

**Rationale**: The CCD API is the modern, supported path. The DisplayConfig module provides PowerShell integration without requiring custom P/Invoke code. MultiMonitorTool's `/SaveConfig` and `/LoadConfig` provide a dead-simple backup plan for the profile system (see `04-profile-system`).

## References

- [DisplayConfig PowerShell module](https://github.com/MartinGC94/DisplayConfig)
- [MultiMonitorTool — NirSoft](https://www.nirsoft.net/utils/multi_monitor_tool.html)
- [Microsoft: ChangeDisplaySettingsEx](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-changedisplaysettingsexa)
- [Microsoft: SetDisplayConfig](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setdisplayconfig)
- [Microsoft: SetDisplayConfig Summary and Scenarios](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/setdisplayconfig-summary-and-scenarios)
- [display-resolution — simpler P/Invoke example](https://github.com/lust4life/display-resolution)
- [Matt Muster: Scripted Screen Resolution and Rotation](https://mattmuster.com/2019/05/30/scripted-screen-resolution-and-rotation/)
- [Changing the primary display on Windows by code](https://blog.lohr.dev/primary-display-windows)
