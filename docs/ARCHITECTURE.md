# Architecture

Nicos Slot Dock is a Swift Package with a pure core library and one AppKit /
SwiftUI executable.

## `SlotDockCore`

The core target owns testable models and policies:

- versioned slot persistence and configuration migration.
- launch-target normalization and duplicate detection.
- system Dock parsing and merge/mirror/off composition.
- running-process identity and transient application tiles.
- notification badge snapshots and context-menu models.
- reveal state, display geometry, and safe-area planning.
- single-instance and hotkey-registration policy.
- reversible system Dock preference snapshots.

The target does not open windows or request macOS permissions. Its behavior is
covered by the headless unit-test suite.

## `SlotDock`

The executable owns operating-system adapters and presentation:

- an AppKit floating panel containing the SwiftUI strip and settings UI.
- workspace notifications for application launch and termination.
- an FSEvents-backed watcher for system Dock preference changes.
- optional Accessibility adapters for windows and Dock badges.
- explicit AppleScript actions for login-item and Dock compatibility changes.
- local OSLog diagnostics.
- a single-instance handoff and deterministic headless self-test.

## Degradation rules

System integrations are capabilities, not startup requirements. A missing
integration must not prevent configuration access. It must not prevent
custom-slot launching.

Optional integrations include Accessibility, Automation, Launch Services
symbols, Dock plist access, and application icons.

The private Launch Services adapter dynamically resolves symbols. If symbols
are absent, it returns an empty result. It is isolated to badge and application
metadata. A future Mac App Store build must replace or remove this adapter.

## Build products

`make build` assembles an ad-hoc-signed local app around the SwiftPM release
binary. `make universal` cross-compiles arm64 and x86_64 binaries, combines
them with `lipo`, and assembles the same app bundle. Only
`make package-release` enables hardened-runtime Developer ID signing and
notarization.
