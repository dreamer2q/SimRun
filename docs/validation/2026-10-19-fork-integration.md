# Fork integration acceptance

Tracking: [fork issue #5](https://github.com/dreamer2q/SimRun/issues/5). Integration starts from fork main `3a9fb48` and preserves its existing Metal mapping, native Photos support and closed-lid motion fix. Camera/signing PR #1 had targeted the preparation branch; this series brings accepted device capabilities into main as separate changes.

Current local checks (2026-10-19, Apple silicon, Xcode 26.2, iOS Simulator 26.2):

| Gate | Checks | Scope |
| --- | ---: | --- |
| Default and devices-enabled core | both pass | Deep strict bundle signature verification; default excludes optional devices |
| Location settings / invalid recovery | 9 + 10 | Idle delegate updates, configured fixes, denied/stop behavior and same-PID file recovery; fixture native actions |
| Camera authorization | 19 | Negative paths, no provider connection |
| Real-image camera | 22 | Frames, photos, stop/recovery and location; real supplied screenshot, not live desktop capture |
| Camera format metadata | 6 | Two source sizes, listed native format before capture, frame dimensions, no discovery restart |
| Screen cache state | 14 | Privacy state transitions; no actual SCStream/TCC exercised |
| AX keyboard ownership and bound typing | 15 | Shared wrapper/different input, stale tokens, callback focus changes, rejection, Unicode and legacy behavior |
| ObjC invocation exception conversion | 5 | Catchable JS errors, CLI failure, same PID and subsequent valid invocation |
| Device identity | 208 + 4 | Native Darwin API/scope assertions and exception recovery, plus Simulator module build/sign |

See [structured results](2026-10-19-fork-integration.json) and [identity details](2026-10-19-device-identity.md). These are local checks, not GitHub CI or universal application acceptance. On Xcode 26.2 the existing CoreAudio SDK-header gap required a build-only compatibility include: place the macOS SDK's `AudioHardwareBase.h` in `build/compat/CoreAudio/`, then append `-Ibuild/compat` to `SIMCC`. No Apple header is vendored.

An initial run of the stock AX button locator timed out. Location checks subsequently used the probe's native action selectors, validating adapter/delegate contracts without claiming AX button-selection success. The separate fresh AX keyboard/input fixture passed. Preserve the failed attempt privately; do not silently count it as passed.

The existing Metal implementation is unchanged. The 2026-10-16 private device-build run captured an actual `newRenderPipelineStateWithDescriptor:error:` CompilerError(2) for a device-only shader; exact paired resource mapping restored the same video's render pipeline and motion, and disabling/recreating reproduced the error. Two final HEVC videos rendered at approximately 30fps; switching and pause/resume passed. Initial display-error count 6 / code -2540 on the first video remained stable, so this is not zero-error video compatibility. Library hashes, paired resources, business APIs and screenshots stay private.

Actual live desktop movement/cropping and certificate-based signing retain their separately dated 2026-10-15/16 acceptance. The current image/cache checks do not repeat those hardware/privacy gates. VAP remains outside this integration. All current owned test Apps and hosts were stopped.

Original MIT attribution and CAMouflage LICENSE/NOTICE remain intact. Publication includes generic source, fixtures and sanitized summaries only.
