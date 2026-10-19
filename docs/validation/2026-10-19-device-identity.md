# Device identity acceptance

The opt-in module in `extras/device-identity` preserves the device-compiled business branch while supplying selected API results only to direct callers in the main executable and embedded business Frameworks. Apple runtime libraries and inserted tooling retain the actual environment. It does not patch any application-specific detection method.

Current checks on Apple silicon, Xcode 26.2 (2026-10-19): 208 native Darwin fixture assertions across enabled, disabled, mismatched root/plist and missing-model configurations; four throw-once recovery cases; iOS Simulator module compilation and strict ad-hoc signature verification. The production source SHA256 matches the independently reviewed and privately accepted 2026-10-16 candidate. See [structured evidence](2026-10-19-device-identity.json).

The earlier private unencrypted device Debug application retained its non-Simulator business branch and reported the configured iPhone model. Search displayed results with actual TCP/200 metrics. The same package without this identity module also searched successfully, so this evidence does not establish that the module repaired an earlier transport failure. Two-video playback and pause/resume required the independent Metal resource adapter already in this fork; they are not identity-module features.

The native Darwin fixtures validate API contracts and caller boundaries, not full iOS hardware parity. Raw environment/plist/CFBundle access, dyld/Mach-O/filesystem inspection, early caches, external wrappers, hardware and attestation remain outside scope. The original repository MIT license is unchanged; no private package, resource, account, raw log or screenshot is published.
