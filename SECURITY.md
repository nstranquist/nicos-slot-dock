# Security policy

## Supported version

Security fixes currently target the latest commit on `main`. The project has
not published a supported binary release yet.

## Report a vulnerability

Use the repository's private GitHub security-advisory form. Do not include
credentials, private configuration, or exploit details in a public issue.

Include the affected commit or version, macOS version and architecture,
reproduction steps, expected impact, and whether the issue needs Accessibility
or Automation permission.

## Sensitive boundaries

Review is especially important for changes involving:

- configuration parsing and atomic writes;
- application, file, URL, and process launch resolution;
- Apple Events and Accessibility permission handling;
- system Dock preference commands and backup restoration;
- private Launch Services symbol lookup;
- login-item registration, code signing, and notarization.

Private Launch Services lookups are optional and fail soft. They must never
become a requirement for launching the app or reading its configuration.
