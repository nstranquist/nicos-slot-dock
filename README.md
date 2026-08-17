# Nicos Slot Dock

[![CI](https://github.com/nstranquist/nicos-slot-dock/actions/workflows/ci.yml/badge.svg)](https://github.com/nstranquist/nicos-slot-dock/actions/workflows/ci.yml)

Nicos Slot Dock is a native macOS launcher strip that works alongside the
system Dock. It stays on your Mac: there is no account, no network client, and
no telemetry.

<img src="https://raw.githubusercontent.com/nstranquist/nicos-slot-dock/main/assets/brand/nicos-slot-dock.png" width="96" height="96" alt="Nicos Slot Dock application icon">

You can:

- add custom applications, files, and URLs
- merge or mirror the system Dock, or show custom slots only
- show running applications and notification badges
- reveal the strip from the screen edge, the menu bar, or an optional shortcut

This repository is the public source. There is no approved downloadable binary
yet. Do not redistribute a locally ad-hoc-signed build as an official release.

![Nicos Slot Dock strip with Finder, Safari, Terminal, Notes, Calendar, and System Settings](https://raw.githubusercontent.com/nstranquist/nicos-slot-dock/main/docs/assets/dock-strip.png)

The strip screenshot uses stock macOS applications in **Off** mode. It does
not show a personal Dock.

![Nicos Slot Dock Settings, Options tab, with pin-open enabled and system Dock integration off](https://raw.githubusercontent.com/nstranquist/nicos-slot-dock/main/docs/assets/settings-options.png)

The settings screenshot is the real Options pane from a source-built app.
Launch at login stays unavailable until the app is installed under
`/Applications`.

## Highlights

- Native AppKit and SwiftUI strip with no Dock icon during normal use
- **Merge** (default): custom slots first, then live system Dock applications
- **Mirror**: system Dock applications only
- **Off**: custom slots only
- Drag an application, file, or URL onto the strip to add a custom slot
- Right-click a tile for launch, reveal, remove, window, and process actions
- Optional running-application dots, notification badges, and transient tiles
- Optional window safe-area inset so content clears the strip
- Launch at login is off by default
- Configuration is a versioned JSON file on disk

## Requirements

- macOS 14 or later
- Swift 6 through Xcode or the Xcode Command Line Tools
- gitleaks only for the complete `make publish-ready` history scan
- ImageMagick only to regenerate the app icon

## Install from source

```sh
git clone https://github.com/nstranquist/nicos-slot-dock.git
cd nicos-slot-dock
make install
```

`make install` builds a release app, signs it ad-hoc, and copies it to
`/Applications/Nicos Slot Dock.app`. Local ad-hoc signing is enough to run the
app on the same Mac. A public binary also needs a Developer ID identity,
notarization, and a visible-device review. See
[the release guide](docs/RELEASING.md).

To build without installing:

```sh
make build             # .build/app/Nicos Slot Dock.app
make run               # build and launch the local app
make test              # Swift unit tests
make headless-smoke    # deterministic app self-test
make verify            # tests, app bundle, signing, plist, and smoke checks
make verify-universal  # arm64 plus x86_64 app verification
make publish-ready     # complete public-source gate
```

To remove the installed app:

```sh
make uninstall
```

If you enabled **Launch at login**, turn that option off in Settings first.

## How it works

Move the pointer to the configured screen edge or click the thin reveal tab.
You can also use the menu-bar item. The strip can stay open when you pin it.

The default **Merge** mode places custom slots before applications from the
system Dock. **Mirror** shows the system Dock applications only. **Off** shows
custom slots only. Optional transient tiles can show running applications that
are not otherwise present.

Configuration is stored in:

```text
~/.config/nicos-slot-dock/slots.json
```

The format is versioned and migrated on load. After an explicit request, the
app keeps a separate backup before it changes system Dock preferences.

## Permissions and system changes

The basic launcher does not require Accessibility or Automation permission.

- Accessibility is optional. It enables window safe-area adjustment. If macOS
  grants access, it can also improve badge and window discovery.
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
