# Human-only signing and notarization setup

Syncorda's GitHub release workflow is ready, but it cannot publish a signed/notarized build until these human-held credentials exist.

## What a human must provide

1. An active Apple Developer Program membership for the release owner.
2. A **Developer ID Application** certificate and its private key, exported as a password-protected `.p12` file.
3. An App Store Connect API key permitted to submit notarizations: key ID, issuer ID, and the `.p8` private key.
4. The final Developer ID signing identity text, typically `Developer ID Application: Legal Name (TEAMID)`.

Never paste any of those values into an issue, pull request, chat, shell history, or repository file.

## Configure GitHub

In the repository's **Settings → Environments → release → Environment secrets**, add:

| Secret | Value |
| --- | --- |
| `APPLE_DEVELOPER_ID_CERTIFICATE_BASE64` | Base64 encoding of the `.p12` file, with no explanatory text. |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12`. |
| `APPLE_KEYCHAIN_PASSWORD` | A new random, single-use CI keychain password. |
| `APPLE_DEVELOPER_ID_APPLICATION` | The exact Developer ID Application signing identity. |
| `APPLE_NOTARY_KEY_ID` | App Store Connect API key ID. |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect issuer ID. |
| `APPLE_NOTARY_PRIVATE_KEY` | Contents of the API key's `.p8` file. |

The workflow uses these only within the protected `release` environment, signs with hardened runtime, notarizes with `notarytool`, staples the ticket, and publishes an arm64 ZIP plus checksum.

## Final human checks

Before triggering **Signed release** from GitHub Actions:

1. Review the exact release tag, release notes, and compatibility claims.
2. Install the notarized ZIP on a clean macOS user account and approve Syncorda's System Audio Recording permission when macOS requests it.
3. Perform the hardware qualification protocol in `Docs/compatibility.md` for the outputs claimed in the release notes.

After these checks, dispatch the workflow with the intended version and `prerelease` selected for the public alpha.
