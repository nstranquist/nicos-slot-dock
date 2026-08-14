# Privacy

Nicos Slot Dock is local-first. The application contains no network client and
does not send analytics, crash reports, configuration, application lists, file
paths, window titles, or usage events to a server.

## Data stored on disk

The app stores user-controlled configuration under
`~/.config/nicos-slot-dock/`:

- `slots.json` contains slots and preferences;
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

- Accessibility can inspect and move visible windows and can read Dock badge
  labels. It is used only when the relevant option is enabled or permission is
  already available.
- Automation can control System Events for explicit login-item and Dock
  compatibility actions. The app asks at the time of the action.
- Launch at login is off by default.

The app remains useful when these permissions are denied.

## Network changes

Any future network feature must be opt-in, documented here before release, and
covered by tests that show what leaves the device. Adding silent telemetry is
not permitted.
