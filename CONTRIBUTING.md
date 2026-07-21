# Contributing to Syncorda

Thanks for helping make local macOS audio routing more reliable.

## Before opening a pull request

1. Discuss large behavior or architecture changes in an issue first.
2. Build and run the deterministic suite:

   ```sh
   swift build
   swift run syncordachecks
   ./scripts/build-app.sh
   ```

3. Keep real-time audio paths allocation-free and lock-free.
4. Update the CLI reference and GUI behavior together whenever a route setting changes.
5. Do not add telemetry, network audio transport, or recording behavior without an explicit privacy design review.

## Hardware testing

Hardware tests are opt-in and should never be required for CI. When testing manually, record the macOS version, processor architecture, source app, output UIDs, sample rates, reconnect/sleep behavior, and whether audio stayed synchronized after ten minutes. Do not attach private recordings or account information to an issue.

## Pull requests

Keep PRs focused, explain user-visible behavior, include test output, and call out any TCC permission, signing, or device-compatibility impact. Maintainers may request a hardware reproduction before merging changes to Core Audio callbacks.

By contributing, you agree that your contributions are licensed under the repository's MIT License.
