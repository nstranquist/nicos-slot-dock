# Source provenance

Nicos Slot Dock began as a product cell inside the private `nicos-tools`
monorepo. This repository reconstructs the application-only history without
rewriting or removing the original commits.

## Reconstructed changesets

Seven source commit objects touch the original product path. Two pairs have
identical application trees because the same staged state was published into
alternate guarded Git lineages. The public history keeps five meaningful
changesets and records both members of each duplicate pair.

| Public changeset | Source commit | Equivalent source commit | Source app tree |
|---|---|---|---|
| Initial application | `902931604d11d8d0899c423d7a278da99eea7e5e` | `af96708ca02d7e0104bdb29d51198ec48140f746` | `bc78c59ed68c51a9c431b064b1267791f4bcaa45` |
| Quality remediation | `525b74440c24a918d4debcd7a2d669c4b24f8e46` | `c6747a90624d5a1a0ca989aa425e368fda0cbb84` | `01b406c18da8034ded779ed3de884a39ddd1ec5c` |
| Desktop refinements | `353d23d4f1c42783bf7bdffc2f7f02bd17646049` | — | `981693ae1b15a5c4d1d0e3c86c6d99546bbe1844` |
| Badge monitoring | `ea3ac53c677c99944c1753fd831d9440f0fa6ace` | — | `ae003443130b17edc3f6a1029025d47c1f0f9d97` |
| Running-app fixes | `1fb69052b1cf5b2a2776547de0dd9ca03c5e33d1` | — | `2d8482a2522a6d9cebf209458ee04a112c0e9a9e` |

Each reconstructed commit retains the original author date and carries
`Source-Commit`, `Equivalent-Source-Commit` where applicable,
`Source-App-Tree`, and `Original-Subject` trailers. Author email addresses are
normalized to the public GitHub noreply address.

## Privacy filter

The import includes Swift source, tests, resources, package/build files, and
the headless smoke harness. It excludes monorepo-only catalog declarations,
internal operator handoffs, quality ledgers, and the monorepo README from every
public commit. Public-native documentation replaces those files in the next
changeset.

This is a history reconstruction, not a claim that the public commit hashes
equal the private source hashes. The recorded app-tree object IDs make the
mapping independently auditable by someone with authorized source access.
