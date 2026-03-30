# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Dev environment with simulated WidowX-200 robot arm (`Dev.TestRobot`)

## [0.1.0] - 2026-03-30

### Added

- Initial release
- Safety controls panel (arm/disarm/force disarm)
- Joint positions table with real-time updates
- Event stream with scrolling
- Commands panel
- Runtime state display
- Status bar with key hints
- Help overlay
- Force disarm confirmation popup
- Keyboard navigation between panels
- Mix task `mix bb.tui --robot MyApp.Robot`
- Headless test suite with Mimic + ExRatatui test backend

[Unreleased]: https://github.com/beam-bots/bb_tui/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/beam-bots/bb_tui/releases/tag/v0.1.0
