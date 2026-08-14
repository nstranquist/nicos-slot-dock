# Nicos Slot Dock

Nicos Slot Dock is a native macOS launcher strip that works alongside the
system Dock. Add custom applications, files, and URLs; merge or mirror the
system Dock; show running applications and notification badges; and reveal the
strip from the screen edge, menu bar, or an optional keyboard shortcut.

The project is open source under the MIT License and is being prepared
for its first public source release. There is currently no approved
downloadable binary. Do not redistribute a locally ad-hoc-signed build as an
official release.

## Requirements

- macOS 14 or later
- Swift 6 through Xcode or the Xcode Command Line Tools
- gitleaks for the complete `make publish-ready` history scan
- ImageMagick only when regenerating the committed app icon

## Build and verify

```sh
make build             # .build/app/Nicos Slot Dock.app
make run               # build and launch the local app
make test              # Swift unit tests
make headless-smoke    # deterministic app self-test
make verify            # tests, app bundle, signing, plist, and smoke checks
make verify-universal  # arm64 plus x86_64 app verification
make publish-ready     # complete public-source gate
```

Local builds use ad-hoc signing by default. `make package-release` fails unless
you provide a Developer ID Application identity and a notarytool keychain
profile. See [the release guide](docs/RELEASING.md).

## How it works

The default **Merge** mode places custom slots before applications from the
system Dock. **Mirror** shows the system Dock applications only. **Off** shows
custom slots only. Optional transient tiles can show running applications that
are not otherwise present.

Move the pointer to the configured screen edge, click the thin reveal tab, or
use the menu-bar item to open the strip. Drag an application, file, or URL onto
the strip to create a custom slot. Right-click a tile for launch, reveal,
remove, window, and process actions.

Configuration is stored in:

```text
~/.config/nicos-slot-dock/slots.json
```

The format is versioned and migrated on load. The app also keeps a separate
backup when you explicitly ask it to change system Dock preferences.

## Permissions and system changes

The basic launcher does not require Accessibility or Automation permission.

- Accessibility is optional. It enables window safe-area adjustment and can
  improve badge/window discovery when already authorized.
- Automation is requested only for explicit settings actions that manage
  another application's login item or change system Dock compatibility.
- System Dock preference actions are user-confirmed and keep a restorable
  snapshot.
- Launch at login is opt-in and off by default.

The app has no network client and sends no telemetry. Diagnostics use local
unified logging. Read [PRIVACY.md](PRIVACY.md) for the complete data boundary.

## Compatibility note

Badge discovery uses documented Accessibility APIs and a fail-soft adapter for
private Launch Services symbols. Apple can change those private symbols in any
macOS update. If they are unavailable, Nicos Slot Dock continues without that
badge source. This implementation is not suitable for Mac App Store
distribution without removing or replacing that adapter.

## Project documentation

- [Architecture](docs/ARCHITECTURE.md)
- [History and provenance](docs/PROVENANCE.md)
- [Release process](docs/RELEASING.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)
- [Changelog](CHANGELOG.md)

## License

Nicos Slot Dock is licensed under the [MIT License](LICENSE).
