# Security policy

## Supported versions

Security fixes target the latest `main` branch and the latest tagged alpha release.

## Reporting a vulnerability

Please use GitHub's private vulnerability-reporting channel for this repository. Do not open a public issue before maintainers have assessed the report.

Useful reports include a clear impact statement, macOS version, Syncorda version, reproducible steps, and a minimal proof of concept. Do **not** include audio recordings, API tokens, profiles containing private device names, or account data.

Syncorda's security-sensitive areas include the local Unix control socket, profile persistence, app signing/notarization, and Core Audio process capture permissions. We aim to acknowledge reports within seven days and provide a remediation plan once reproduced.
