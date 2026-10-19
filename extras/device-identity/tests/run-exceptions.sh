#!/bin/bash
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$here/../../artifacts/device-parity-20261016/identity-exceptions-v2}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
app="$out/ExceptionFixture.app"
mkdir -p "$app/Contents/MacOS" "$app/Frameworks/ThrowOnce.framework/Resources"
python3 - "$out" <<'PY'
import pathlib,plistlib,sys
out=pathlib.Path(sys.argv[1]);app=out/'ExceptionFixture.app'
info={'CFBundleIdentifier':'dev.simrun.identity-exception-fixture','CFBundleName':'ExceptionFixture','CFBundleExecutable':'ExceptionFixture','CFBundlePackageType':'APPL','CFBundleVersion':'123','DTPlatformName':'iphonesimulator','DTSDKName':'iphonesimulator27.1','CFBundleSupportedPlatforms':['iPhoneSimulator']}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
(out/'original.plist').write_bytes(plistlib.dumps(dict(info,DTPlatformName='iphoneos',DTSDKName='iphoneos27.1',CFBundleSupportedPlatforms=['iPhoneOS'])))
info={'CFBundleIdentifier':'dev.simrun.exception-business-fixture','CFBundleExecutable':'ThrowOnce','CFBundlePackageType':'FMWK'}
for rel in ['Resources/Info.plist','Info.plist']:(app/'Frameworks/ThrowOnce.framework'/rel).write_bytes(plistlib.dumps(info))
PY
cc=(xcrun --sdk macosx clang -arch arm64 -fobjc-arc -O2 -fno-optimize-sibling-calls -Wall -Wextra -Werror)
"${cc[@]}" -dynamiclib "$here/tests/exception-original.m" -framework Foundation -o "$out/ExceptionOriginal.dylib"
# A real dependency ensures the pre-hook constructor runs before identity records original IMPs.
"${cc[@]}" -dynamiclib "$here/identity.m" "$out/ExceptionOriginal.dylib" -framework Foundation -o "$out/Identity.dylib"
"${cc[@]}" -dynamiclib -DSR_SNAPSHOT=SRThrowSnapshot "$here/tests/snapshot.m" -framework Foundation -o "$app/Frameworks/ThrowOnce.framework/ThrowOnce"
"${cc[@]}" "$here/tests/exception-main.m" "$out/ExceptionOriginal.dylib" -framework Foundation -o "$app/Contents/MacOS/ExceptionFixture"
for binary in "$out/ExceptionOriginal.dylib" "$out/Identity.dylib" "$app/Frameworks/ThrowOnce.framework/ThrowOnce"; do codesign --force --sign - "$binary"; done
export SIMRUN_DEVICE_IDENTITY=1 SIMRUN_DEVICE_IDENTITY_APP_ROOT="$app" SIMRUN_DEVICE_IDENTITY_MODEL=iPhone18,1
export SIMRUN_DEVICE_IDENTITY_ORIGINAL_INFO="$out/original.plist" SIMULATOR_IDENTITY_FIXTURE=simulator-marker
export DYLD_INSERT_LIBRARIES="$out/Identity.dylib"
for mode in 1 2 3 4; do "$app/Contents/MacOS/ExceptionFixture" "$mode" > "$out/mode-$mode.json"; done
echo "$out"
