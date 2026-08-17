# Contributing

Thank you for helping improve Nicos Slot Dock.

## Before changing code

Open an issue for behavior changes that affect permissions, system Dock
preferences, configuration migration, private framework use, or release
signing. Small fixes and test improvements can go directly to a pull request.

## Development checks

Use macOS 14 or later with Swift 6. Before submitting a change, run:

```sh
make test
make verify
make verify-universal
```

Maintainers run `make publish-ready` before a source release. New behavior must
include deterministic tests where practical. If a permission is absent, the
dependent behavior must fail safely.

## Pull requests

- Keep each change focused.
- Explain user-visible behavior and security or privacy impact.
- Update `CHANGELOG.md` for user-visible changes.
- If data handling, logging, permissions, or network access changes, update
  `PRIVACY.md`.
- Do not commit build output, local configuration, signing material, or
  notarization credentials.
- Do not commit screenshots that show a personal Dock, files, wallpaper,
  or live application window thumbnails. Use stock applications and Off
  mode, or crop until only product chrome remains.

By contributing, you agree that your contribution is licensed under the MIT
License.
