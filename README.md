# Parsec Event Executor

This repository now contains a PowerShell 7 recipe executor for Parsec-related `DESKTOP` and `MOBILE` transitions.

What is implemented:

- TOML-backed recipe parsing
- dependency-gated recipe execution
- JSON-backed runtime state and profile persistence
- built-in display/profile/process/service/command ingredients
- placeholder mission recipes for `enter-mobile` and `return-desktop`
- approval gating so no concrete mode values are encoded before user sign-off

What is not implemented yet:

- real display mutation through `DisplayConfig`
- Parsec log tailing
- Task Scheduler daemon hosting
- approved concrete `MOBILE` and `DESKTOP` mode definitions

The implementation status and required approval input are documented in `docs/plan/implementation-plan.md`.
