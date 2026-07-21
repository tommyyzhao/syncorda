# Releasing Syncorda

## Alpha distribution contract

Public alpha builds are Apple-Silicon only until Intel has passed the compatibility matrix. Ship a versioned `Syncorda.app` ZIP with a SHA-256 checksum and release notes that state the alpha limits.

## Local verification

```sh
swift build
swift run syncordachecks
SYNCORDA_VERSION=0.1.0-alpha.1 ./scripts/build-app.sh
./scripts/verify-bundle.sh
```

For a bundle validation that must not replace a running local app, choose a separate output directory:

```sh
SYNCORDA_APP_OUTPUT_DIR=tmp/release-validation ./scripts/build-app.sh
./scripts/verify-bundle.sh tmp/release-validation/Syncorda.app
```

## Signed public build

Set `DEVELOPER_ID_APPLICATION` to a valid Developer ID Application signing identity, and set a positive integer `SYNCORDA_BUILD` for the release build number. The build script uses that identity with hardened runtime options. Submit the resulting ZIP with `xcrun notarytool`, staple the notarization ticket, re-verify the signature, and test installation on a clean user account before publishing.

Keep signing certificates and App Store Connect API credentials in protected GitHub environment secrets. Never commit certificates, private keys, profiles, app passwords, or notarization logs containing secrets.

See [human-only signing setup](signing-setup.md) for the credentials and final approval steps required before the first signed public binary.

## Tag checklist

1. Update `CHANGELOG.md`, version, compatibility matrix, and known issues.
2. Ensure CI and manual hardware checks pass.
3. Create an annotated `vX.Y.Z` tag.
4. Build, sign, notarize, staple, checksum, and verify the app.
5. Create GitHub Release notes with the compatibility/permission limits.
6. Enable private vulnerability reporting and Discussions before announcing publicly.
