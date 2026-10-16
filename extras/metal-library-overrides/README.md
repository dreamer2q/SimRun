# Optional simulator Metal library mapping

Some simulator builds embed device-only Metal libraries that load but fail pipeline
compilation. This process-local module substitutes an explicitly supplied matching
simulator library by exact input SHA256 and size. It is disabled by default and
requires no camera, location, VAP, or other optional SimRun module.

Dependencies: Apple silicon, Xcode with an iOS Simulator SDK and `metal-objdump`,
and paired device/simulator libraries supplied by the caller. Matching shader
interfaces remain the caller's responsibility. No application resources, mappings,
private hashes, or third-party shader binaries are included.

```sh
bash extras/metal-library-overrides/build.sh
python3 extras/metal-library-overrides/create-manifest.py \
  --input-library /absolute/device.metallib \
  --simulator-library /absolute/simulator.metallib --manifest /absolute/map.json
SIMRUN_METAL_LIBRARY_MAP=/absolute/map.json build/bin/simrun run \
  --insert "$PWD/build/metal-library-overrides/SimRunMetalLibraryOverrides.dylib" \
  /absolute/App.app
```

The manifest records input/output SHA256, sizes and the replacement path. Runtime
validation checks bounded files and exact bytes, then compiles every supported
entry on `MTLSimDevice` before enabling the mapping. Preflight supports at most 32
simple vertex, fragment or compute entries; complex required pipeline state is
unsupported. Invalid reconfiguration retains the previous mapping. Unmatched
libraries pass through unchanged; global Metal validation is not modified.

`SRMetalLibraryOverrides` exposes `configureWithManifest:`, `status` and `disable`.
Disable affects future calls; an in-flight call may finish with its snapshot. Do
not unload the module in a live process. Restart or re-enter playback to recreate
an already-failed renderer. Loading without configuration installs no hook.

```sh
python3 extras/metal-library-overrides/run-tests.py \
  --input-library /absolute/device.metallib --simulator-library /absolute/simulator.metallib \
  --module /absolute/SimRunMetalLibraryOverrides.dylib --expected-module-sha256 SHA256 \
  --simrun /absolute/simrun --output /absolute/new-private-output-directory
```

The probe checks exact replacement, passthrough, disable/re-enable and invalid
configuration rejection. Actual playback additionally requires changing video-only
pixels and successful render pipelines; library load success alone is insufficient.
The preferred permanent fix is correct simulator resource packaging in the SDK.
MIT; see [LICENSE](LICENSE). Supplied shader resources retain their own licenses.
