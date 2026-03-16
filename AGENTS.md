# Parsec Event Executor

This project implements a parsec connect/disconnect "event" execution flow.

## Background

The local development machine is a desktop with multiuple monitors, however, the system is also used
remotely via Parsec on a phone screen.

The physical topology of the devices means the actual screen arrangement, dpi and text scaling values need to be modified
before and after every connect and disconnect event. Parsec does handle resolution switching but not orientation flipping
and complex event registration.

## Aim

To create a modular script that can execute a sequence of custom actions.
- set/reset the connected displays (n number -> 1 display when Parsec is connected -> reset to original)
- set/reset dpi scaling (using non-custom dpi scaling values that do not require login restart)
- set/reset display orientation
- execute and start apps on connect/kill them on disconnect.

## Bounds

Windows 11 desktop system with 2+ connected displays. Remote parsec is an android phone.
pwsh available (modern powershell).

The framework needs to implement proper queue and event verification - and needs to be highly configurable and
customizable.
- architect recipe based system
- define ingredient schema (a desreet action to execute with customizable arguments)
- define toml or yaml config to set up and control recipes
- ingredients to act as "capability modules", e.g. a mpoulde capable of setting resolutions; changing orientation; change font size; ...
- recipe engine must be accounting for the fact that event execution might be async as it bubbles through the system.
- recipe engine must be able to define constratins and dependencies - e.g. ingredient 1 dependends on ingredient 2 and 3
- recipe engine must be rosubst, and implement error handling, error logging, expontntial retry mechanisms and failsave behaviour.
- projects needs a robust "current state" persistance. This is crucial for identifying  current window layout and settings, window and modnitor placement, etc to restore to original state.
- must support a default profile (baseline system state) and user-defined connect recipes.

## Best practices

Ground research and knowledge using context7 mcp and online discovery. Documentation consultation is key before implemneting features.
- WEhen planning ensure a descreet research grounding phase is always included in planning.
- When verifying project ensure code review also grounds review in dev docs - this makes verification process more robust.
- Implement testing - use powershell best practices
- Do not implement tautological tests, but mocking complex system backends is okay and expected given that we do not want to modify life system settings.

## References

Research and adrs are persisted docs/ and should be speparated into docs/research/ docs/adr docs/audit folders.
Audits must contain audt cycle tasks that have been identified and need triaging and fixing.
