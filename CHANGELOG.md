# Changelog

This project follows [Semantic Versioning](https://semver.org/).

## Unreleased

## 0.3.4 - 2026-08-17

- Scan complete Git history with the gitleaks CLI in CI. The previous action
  failed on the root commit because it requested a parent that does not exist.

## 0.3.3 - 2026-08-17

- Sign each app bundle with the Apple Events Automation entitlement.
- Stop the build if the signed app does not contain the required entitlement.
- Include the entitlement file in the source-publication gate.
- Add privacy-safe product screenshots of the launcher strip and Settings.
- Show the real fault text in the status-item error row.
- Recompose the strip when running-app identity changes so other-path copies appear immediately.
- Keep headless smoke from changing the installed app's login item.
- Run CI on macOS 15 with Xcode 16 and a full-history privacy scan.

This version is the current public-source tag candidate.

## 0.3.2 - 2026-08-14

- Roll back in-memory slot reordering when the atomic configuration write fails.
- Scan test history for private paths while allowing only named synthetic homes.
- Document the GitHub private-reporting setup and safe fallback procedure.
- Prepare the privacy-filtered standalone MIT repository.
- Adopt Nicos Slot Dock as the canonical public product name.
- Add universal-build, privacy, secret, CI, and notarized-release gates.
- Add public contributor, security, privacy, provenance, and architecture docs.
- Approve an identity-bound catalog logo and reviewed public portfolio manifest.
- Pin GitHub Actions to verified upstream commit digests.
- Expose the complete `make publish-ready` source gate through the external catalog manifest.
- Give the complete gate enough time for a cold Swift and universal build.

This version was an untagged public-source candidate.

## 0.3.1 - 2026-08-14

- Add running-application reconciliation and instance-aware context menus.
- Improve notification badge and live application-icon discovery.
- Expand deterministic unit and headless smoke coverage.
- Harden configuration, Dock composition, and fail-soft system integration.

This version is the reconstructed source baseline. It has not been tagged or
published as a downloadable binary.
