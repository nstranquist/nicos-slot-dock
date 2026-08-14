# Privacy

Nicos Slot Dock is local-first. The application contains no network client. It
does not send analytics, crash reports, configuration, application lists, file
paths, window titles, or usage events to a server.

## Data stored on disk

The app stores user-controlled configuration under
`~/.config/nicos-slot-dock/`:

- `slots.json` contains slots and preferences.
- `system-dock-prefs-backup.json` contains the Dock preference values needed
  to undo an explicit compatibility action.

Development and self-test builds can redirect configuration and reports with
documented environment variables. Build output remains under `.build/`.

## Local diagnostics

Diagnostics use Apple's unified logging system with subsystem
`com.nstranquist.nicos-slot-dock`. Potentially identifying values use private
OSLog interpolation. Logs remain subject to the retention and access rules of
the local macOS installation.

## Optional permissions

- Accessibility can inspect and move visible windows. It can also read Dock
  badge labels. The app uses it only for an enabled feature or an existing
  authorization.
- Automation can control System Events for explicit login-item and Dock
  compatibility actions. The app asks at the time of the action.
- Launch at login is off by default.

If these permissions are denied, the app remains useful.

## Network changes

Any future network feature must be opt-in. This document must describe it
before release. Tests must show what leaves the device. Silent telemetry is not
permitted.
