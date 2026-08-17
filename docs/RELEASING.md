# Releasing

Source publication and binary distribution have separate gates.

## Source release

From a clean `main` checkout, run:

```sh
make publish-ready
```

The target:

- runs unit tests.
- assembles and smoke-tests the app.
- cross-compiles a universal binary.
- verifies Git history for private paths and personal email.
- runs gitleaks.
- verifies required public files.
- requires a clean working tree.

Review the exact commit and create a SemVer tag only after the source gate is
green. Do not attach `.build` output from the default local build to a public
release.

After the GitHub repository exists:

1. Open **Settings → Security → Code security**.
2. Enable **Private vulnerability reporting**.
3. Confirm the repository security page exposes a private report form.
4. Confirm the public issue templates do not ask for vulnerability details.
5. Create `v0.3.3` only after the pushed commit passes the source gate.

The canonical source identity is **Nicos Slot Dock** in the
`nicos-slot-dock` repository. Complete a trademark clearance before commercial
promotion if the owner decides that the market risk warrants it.

## Binary release

A public macOS download requires:

1. a Developer ID Application identity in the signing keychain.
   This machine currently has only `Apple Development`. That identity
   is enough for local `make install`. It is not enough for
   `make package-release`.
2. a notarytool keychain profile containing Apple notarization credentials.
3. visible UI, Accessibility, Automation, multi-display, second-launch, and
   natural-soak checks on the candidate version.
4. a clean source-publication gate.

Then run:

```sh
make package-release \
  CODE_SIGN_IDENTITY="Developer ID Application: Example (TEAMID)" \
  NOTARY_PROFILE="notary-profile"
```

The target builds arm64 and x86_64. It combines them into one app. It enables
the hardened runtime and timestamp. It signs the app with the Apple Events
Automation entitlement. The build stops if the signature omits that
entitlement. The target submits a zip to Apple and waits for notarization. It
staples and validates the ticket. It runs Gatekeeper assessment. Then it emits
a final zip and its SHA-256 file.

Never commit certificates, private keys, App Store Connect keys, Apple account
credentials, or the notary profile. If notarization or Gatekeeper assessment
fails, publish no binary.
