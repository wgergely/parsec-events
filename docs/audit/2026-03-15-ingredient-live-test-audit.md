# Live Ingredient Test Audit — 2026-03-15

## Testing Flow

This audit tracks per-ingredient live verification on real hardware. The workflow is:

1. **Scope**: Test ingredients individually, independent of recipes. Recipes are out of scope.
2. **Apply**: Run the ingredient with specific arguments via `Invoke-ParsecIngredient`.
3. **Pause for verification**: After apply, stop and ask the user to visually confirm the change took effect. Use this prompt format:
   > "I have run ingredient `{name}` with `{settings}`. The run has `{outcome}`. Did you observe `{expected state}`?"
4. **Unroll (reset)**: Run the ingredient reset using the token from apply.
5. **Pause for verification**: After reset, stop and ask the user to visually confirm the original state was restored. Use this prompt format:
   > "Did the `{ingredient}` return to original state?"
6. **Record**: Update the status table below with the result and any defects found.
7. **Move to next ingredient**: Only after user sign-off on both apply and reset.

The user is the expert reviewer and must sign off on every ingredient before it is marked verified.

## Testing Order

**Phase 1 — Safe, no display disruption:**
1. `system.set-theme` — cosmetic only
2. `display.set-textscale` — text size, broadcast verification
3. `command.invoke` — runs a command, no system state
4. `process.start` / `process.stop` — process lifecycle
5. `service.start` / `service.stop` — service lifecycle
6. `sound.set-playback-device` — audio device switch

**Phase 2 — Display mutations (single monitor safe):**
7. `display.set-uiscale` — DPI change, requires sign-out awareness
8. `display.set-scaling` — composite (text + ui)
9. `display.set-resolution` — resolution change on active monitor
10. `display.set-orientation` — orientation flip
11. `display.ensure-resolution` — resolution with NVIDIA custom mode fallback

**Phase 3 — Topology (dangerous on Parsec single-monitor):**
12. `display.set-primary` — already VERIFIED (2026-03-14)
13. `display.set-enabled` — enable/disable monitors
14. `display.set-activedisplays` — multi-monitor selection
15. `display.persist-topology` — capture/restore topology
16. `display.snapshot` — full state capture/restore

**Phase 4 — Backend-specific:**
17. `nvidia.add-custom-resolution` — NVIDIA adapter required

## Environment

- Connected via Parsec (single active monitor: PA278CV at 3000x2000, scale 175%, text scale 100%)
- Secondary monitors (QBQ90 x3) all disabled
- Platform: Windows 11 Pro

## Ingredient Status

| # | Ingredient | Apply | Reset | Status | Notes |
|---|-----------|-------|-------|--------|-------|
| 1 | `command.invoke` | | | PENDING | |
| 2 | `display.ensure-resolution` | | | PENDING | |
| 3 | `display.persist-topology` | | | PENDING | |
| 4 | `display.set-activedisplays` | | | PENDING | Dangerous on single-monitor Parsec |
| 5 | `display.set-enabled` | | | PENDING | Dangerous on single-monitor Parsec |
| 6 | `display.set-orientation` | | | PENDING | |
| 7 | `display.set-primary` | PASS | PASS | VERIFIED (2026-03-14) | Apply + reset with position preservation |
| 8 | `display.set-resolution` | | | PENDING | |
| 9 | `display.set-scaling` | | | PENDING | Composite (text + ui) |
| 10 | `display.set-textscale` | | | PENDING | Broadcast-only path, no window cycling |
| 11 | `display.set-uiscale` | | | PENDING | |
| 12 | `display.snapshot` | | | PENDING | |
| 13 | `nvidia.add-custom-resolution` | | | PENDING | Requires NVIDIA backend |
| 14 | `process.start` | | | PENDING | |
| 15 | `process.stop` | | | PENDING | |
| 16 | `service.start` | | | PENDING | |
| 17 | `service.stop` | | | PENDING | |
| 18 | `sound.set-playback-device` | | | PENDING | |
| 19 | `system.set-theme` | PASS | PASS | VERIFIED | Light→Dark→Light, broadcast propagated |

## Defects

(None yet)
