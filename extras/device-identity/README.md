# Business-facing device identity

An optional compatibility module for testing an unencrypted **device Debug build** in SimRun. Device-build conversion preserves the business code compiled for iPhoneOS. This module supplies a device view at selected business API boundaries while the Simulator runtime retains its actual environment and bundle metadata.

## Build and configure

```sh
extras/device-identity/build.sh
```

Insert `build/device-identity/SimRunDeviceIdentity.dylib` into the App using `simrun run --insert`. Set all four variables explicitly before launch:

```text
SIMRUN_DEVICE_IDENTITY=1
SIMRUN_DEVICE_IDENTITY_APP_ROOT=/absolute/path/to/the/converted/Example.app
SIMRUN_DEVICE_IDENTITY_ORIGINAL_INFO=/absolute/path/to/original/device/Example.app/Info.plist
SIMRUN_DEVICE_IDENTITY_MODEL=iPhone18,1
```

`APP_ROOT` must resolve to the running process's exact `NSBundle.mainBundle.bundlePath`, which can differ from the original device App path after conversion. The original plist must identify iPhoneOS. Missing/invalid configuration leaves all behavior unchanged. The source App and plist are never edited by this module.

Only direct calls originating from the main executable or a Mach-O under that App's `Frameworks/` receive the device view. Canonical paths enforce directory boundaries. Apple framework bundle identifiers (`com.apple.*`), `libswift*`, `SimRun*`, this module, and every image in the original `DYLD_INSERT_LIBRARIES` are excluded even when copied under `Frameworks/`. Other processes and runtime libraries receive their original results. An unrecognized caller is passed through.

## API coverage

| API | Business view | Preserved |
| --- | --- | --- |
| `getenv` | Hide `SIMULATOR_*`, `SIMRUN_*`, `SIMRUND_*`, `SIMNS_*`, `SIMAPP_*`, `DYLD_*`, `XPC_SIMULATOR_*`, and `IPHONE_SIMULATOR_ROOT` | Other keys, their original storage, `HOME`, `PATH`, the real process environment |
| `NSProcessInfo.environment` | Immutable copy excluding the same keys | Original dictionary and other entries |
| Main `NSBundle.infoDictionary` and `objectForInfoDictionaryKey:` | Original device `DTPlatformName`, `DTSDKName`, `CFBundleSupportedPlatforms` | All other fields, business version, other bundles, plist bytes on disk |
| `uname` | Replace `machine` with the configured model after original success | Other fields, failure return, original post-call `errno` |
| `sysctlbyname("hw.machine")` and `sysctl({CTL_HW, HW_MACHINE})` | Same model, NUL-inclusive size, length query, Darwin short-buffer behavior | Other keys, write requests, unsupported forms |

A short `hw.machine` buffer returns `-1` with `ENOMEM`, sets `*oldlenp = 0`, and leaves buffer bytes untouched. Success preserves entry `errno`. Safe Mach copy-in/out returns `EFAULT` for invalid output/length pointers. `getenv` does not fabricate temporary strings: an unknown key returns the original API's pointer; a hidden key returns `NULL`.

The runtime's dyld platform, Metal device, VideoToolbox, and UIKit implementation are unchanged. No App-specific `isSimulator` method is patched.

## Verification

```sh
extras/device-identity/tests/run.sh
extras/device-identity/tests/run-exceptions.sh
```

The native arm64 fixture verifies caller selection using separate main, embedded business, embedded Apple-identified, external, and injected images. It also verifies bundle isolation, business-version preservation, environment isolation, size/short-buffer/errno/EFAULT behavior, MIB/name consistency, and 300 parallel business/infrastructure snapshots. Enabled and disabled/mismatched configurations produce local JSON evidence under `artifacts/device-parity-20261016/identity-fixture/`.

The throw-once fixtures install original implementations before identity hooks and inject exceptions independently into `environment`, `infoDictionary`, `objectForInfoDictionaryKey:`, and embedded-Framework caller classification. Each asserts that the original exception reaches the caller and subsequent environment/bundle views still work. The frozen pre-fix source fails these recovery assertions.

These fixtures validate API contracts on Darwin. The iOS Simulator dylib is separately compiled and signed. Real App search, network transport, and video playback require a separate runtime acceptance run.

Runtime diagnostics: `+[SRDeviceIdentity status]` returns `enabled`, `model`, and the six `calls` counters in this order: hidden `getenv`, `environment`, bundle, `uname`, `sysctlbyname`, `sysctl`. A SimRun scripting bridge or injected probe is outside business scope, so direct identity reads performed by that probe intentionally see the real runtime view.

## Boundaries

This is a scoped compatibility view, not a claim that every device inspection API is indistinguishable from hardware. Raw `environ`, direct plist/CFBundle reads, Mach-O platform commands, dyld image enumeration, filesystem layout, hardware services, and attestation remain separate contracts. Simulator-compiled constant branches still require the device build. Identity reads performed before this module's constructor publishes readiness are passed through; existing framework caches are not rewritten.

Caller classification uses only the immediate call site and never walks up the stack to treat an Apple runtime call as a business call. Calls through an intermediate external wrapper can therefore remain outside scope. Image results are cached with a mutex and removed on image unload. Re-entrant classification is guarded per thread. Every depth guard is balanced with `@try/@finally`: original exceptions still propagate, and catching an exception does not disable identity behavior on that thread. All original Objective-C implementations are recorded before hooks are installed, then readiness is published atomically.

`getenv` interposition is already active during libSystem initialization. The readiness check and TLS-dependent caller classifier are separate non-inlined functions so an optimizing compiler cannot resolve thread-local storage before TLS is initialized.

The injected module must remain loaded for the process lifetime. Unloading it with `dlclose` is unsupported because its interposers, Objective-C implementations, and dyld removal callback remain registered.

## License

MIT; preserves the upstream SimRun attribution in the repository [LICENSE](../../LICENSE).
