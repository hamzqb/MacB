# Releasing MacB

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` and add release notes to `CHANGELOG.md`.
2. Run `./scripts/test.sh`, `swift build`, and `./scripts/package-release.sh`.
3. Verify both artifacts against `dist/SHA256SUMS.txt` and run the packaged app's `--smoke-test`.
4. Commit the release, create an annotated `vX.Y.Z` tag, and push the tag. GitHub Actions verifies the tag/version match, builds universal2 artifacts and publishes the release.
5. Test first launch, permission grant/revocation, Dock hover, switcher, media, file shelf, session lock and sleep/wake on a clean macOS account.

For a warning-free public release, configure repository secrets:

- `DEVELOPER_ID_CERTIFICATE_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `DEVELOPER_ID_APPLICATION`
- `RELEASE_KEYCHAIN_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_PASSWORD`

The workflow fails closed when any secret is absent. It tests the tagged commit, imports the certificate, signs with hardened runtime, submits the app to Apple, staples the ticket, validates Gatekeeper acceptance, verifies checksums and runs the packaged smoke test before publishing. `scripts/package-release.sh` can still create an ad-hoc local artifact for development, but the public workflow never publishes it.

Rollback means marking the affected GitHub Release as a pre-release, restoring the prior tag as the latest stable release, and publishing a patch release. Never replace an existing release archive without changing its version and checksum.
