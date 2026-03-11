# Profile System: Saving and Restoring Display States

## Status: Architecturally Straightforward — Implementation Details Depend on API Choice

## Problem Statement

The automation must switch between two known-good configurations: "desktop mode" (multi-monitor, native resolutions, landscape, default scaling) and "mobile mode" (single monitor, 2000x3000, portrait, 300% UI / 130% text scaling). Each configuration is a bundle of interdependent settings that must be captured, stored, and reapplied atomically. The profile system is the data layer that enables this.

## Research Findings

### What Constitutes a "Profile"

A complete display profile must capture the following state:

| Setting | Source | Persistence Mechanism |
|---|---|---|
| Monitor topology (which displays active) | CCD API / `QueryDisplayConfig` | Serialized path/mode arrays |
| Per-monitor resolution | CCD API | Part of source mode info |
| Per-monitor orientation | CCD API | Part of target mode info |
| Per-monitor position (desktop layout) | CCD API | Part of source mode info |
| Per-monitor refresh rate | CCD API | Part of target mode info |
| Per-monitor DPI scaling | Registry: `HKCU\...\PerMonitorSettings` | Registry export |
| System text scaling | Registry: `HKCU\...\Accessibility\TextScaleFactor` | Registry export |
| Primary monitor designation | CCD API | Flag in path info |

### Storage Options

#### Option A: DisplayConfig Module XML Export

The [DisplayConfig](https://github.com/MartinGC94/DisplayConfig) PowerShell module supports exporting the full display configuration to XML via PowerShell's `Export-Clixml`. This captures the CCD API state in a serializable format that can be re-imported and applied.

Advantages:
- Native PowerShell serialization; no custom format to maintain.
- The module handles adapter ID remapping on restore, which is critical when hardware paths change between sessions.
- Atomic apply: multiple settings are aggregated and committed in a single `SetDisplayConfig` call.

Limitations:
- Does not capture DPI scaling or text scaling (these are registry values outside the CCD API's scope).
- The XML format is opaque — not human-editable for manual adjustments.

#### Option B: MultiMonitorTool Config Files

[MultiMonitorTool](https://www.nirsoft.net/utils/multi_monitor_tool.html) uses its own `.cfg` format for `/SaveConfig` and `/LoadConfig`. This captures resolution, position, orientation, and active/inactive state.

Advantages:
- Single-command save and restore.
- The `.cfg` file is plain text and human-readable.
- No PowerShell module dependency.

Limitations:
- Like DisplayConfig, does not capture DPI or text scaling.
- Less granular control than the CCD API — it's a black-box save/restore.
- External tool dependency (must be distributed alongside the script).

#### Option C: Composite Profile (Recommended)

Neither option alone captures the full state. The recommended approach is a composite profile that combines:

1. **Display topology and geometry**: Captured via the CCD API (either DisplayConfig module or MultiMonitorTool).
2. **DPI scaling values**: Captured via registry read of `PerMonitorSettings`.
3. **Text scaling value**: Captured via registry read of `Accessibility\TextScaleFactor`.

The profile is stored as a directory or a single structured file (JSON or TOML) containing pointers to the sub-components:

```
profiles/
  desktop/
    display.xml          # DisplayConfig export OR MultiMonitorTool .cfg
    scaling.json         # { "monitors": { "<id>": <DpiValue> }, "textScale": 100 }
  mobile/
    display.xml
    scaling.json
```

### Profile Capture Workflow

The initial setup requires capturing both profiles manually:

1. Physically arrange the desktop into the desired multi-monitor layout.
2. Run the capture command → saves "desktop" profile.
3. Manually configure the mobile mode (single monitor, 2000x3000, portrait, 300% DPI, 130% text).
4. Run the capture command → saves "mobile" profile.

After initial capture, the automation toggles between the two stored profiles. Profiles should only need to be re-captured if the physical hardware changes (new monitor, new GPU).

### Profile Restore Ordering

The order in which settings are applied matters:

1. **First: Monitor topology** — enable/disable monitors, set primary. This must happen first because DPI settings are per-monitor, and the monitor IDs may change when topology changes.
2. **Second: Resolution and orientation** — set geometry on the now-active monitors.
3. **Third: DPI scaling** — write registry values for the active monitor IDs.
4. **Fourth: Text scaling** — write the accessibility registry value.
5. **Fifth: Shell restart** — restart `explorer.exe` to pick up DPI/text changes.

This ordering avoids writing DPI values for monitors that haven't been activated yet, and ensures the shell restart happens last (once all settings are in their final state).

### Edge Case: Profile Corruption and Fallback

If a profile fails to apply (e.g., a monitor is physically disconnected that the profile expects), the system should:

1. Detect the failure (CCD API returns an error code; registry write for a nonexistent monitor ID fails silently but has no effect).
2. Log the failure.
3. Attempt a "safe mode" fallback: apply only the settings that are valid for the currently connected hardware.
4. Never leave the system in a half-applied state — if topology change fails, do not proceed to DPI changes for a topology that didn't materialize.

## Open Questions Requiring Empirical Validation

1. **Monitor ID stability**: When switching from three monitors to one and back, do the `PerMonitorSettings` registry keys use stable identifiers? If not, the profile capture must map IDs by hardware descriptor (EDID) rather than by the ephemeral path string.

2. **DisplayConfig module restore fidelity**: Does `Import-Clixml` + apply faithfully restore all aspects of a complex multi-monitor layout (positions, primary designation, refresh rates)?

3. **Profile size and complexity**: How large are the serialized profiles? Are there any limits to what `Export-Clixml` can round-trip?

4. **First-run UX**: How should the initial profile capture be guided? A setup wizard or a simple "run this command while in desktop mode, then run it again while in mobile mode" approach?

## Architecture Decision Required

**Decision**: Use a composite profile system. Display topology and geometry are captured via the DisplayConfig module (CCD API). DPI and text scaling are captured via direct registry reads. Both are stored as files in a versioned profile directory.

**Rationale**: No single tool captures the full state. The composite approach keeps each subsystem's data in its native format (XML for display config, JSON for scaling values), making debugging straightforward. The profile directory structure is simple and version-controllable.

## References

- [DisplayConfig PowerShell module — export/import support](https://github.com/MartinGC94/DisplayConfig)
- [MultiMonitorTool — /SaveConfig and /LoadConfig](https://www.nirsoft.net/utils/multi_monitor_tool.html)
- [MultiMonitorTool usage examples](https://github.com/danielleevandenbosch/MultiMonitorTool)
- [MonitorSwapAutomation — profile-based display switching (Sunshine)](https://github.com/Nonary/MonitorSwapAutomation)
- [Microsoft: DPI-related registry settings](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/dpi-related-apis-and-registry-settings)
