# Scoped decoder attribute compatibility

Validation on 2026-10-20: Apple silicon, macOS 15.7.9, Xcode 26.2, iOS Simulator 26.2.

The optional shim copies the destination pixel-buffer attribute dictionary, including nested dictionaries, using CFType ownership callbacks before the named decoder calls `VTDecompressionSessionCreate`. Other immediate callers pass through unchanged. It does not change the app binary, decoder results, renderer or host permissions.

## Current checks

- A fresh isolated NULL-callback baseline crashed with exit 139 during CoreVideo allocation.
- The matching typed-callback control decoded 45/45 frames with zero session, decode and output callback statuses.
- The freshly rebuilt scoped adapter completed 100 sessions / 4500 decoded frames with zero statuses. The broad diagnostic switch was unset.
- In a private, unencrypted arm64 device-built target app converted by the fork-main build, the previously crashing transition reached its real success page. The scoped adapter recorded successful session creation. This is application transition evidence, not a video-rendering or photo acceptance claim.
- Standalone module/fixture builds and strict code-signature validation passed. Default `make core` and the ordinary camera bundle remain independent.

Reproduce with `bash extras/devices/vap/build.sh` and the commands in `extras/devices/vap/README.md`. The baseline intentionally crashes only a disposable test fixture. Default builds do not silently insert this module; opt in with `--insert` for the affected test app.

MIT attribution remains unchanged. No private app, resource, shader, SDK header, account information, screenshot, raw log, or captured response is included. Raw local observations are retained separately.

Refs #16.
