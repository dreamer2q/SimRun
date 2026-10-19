#!/bin/bash
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$here/../../artifacts/device-parity-20261016/identity-fixture}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
app="$out/IdentityFixture.app"
mkdir -p "$app/Contents/MacOS" "$app/Frameworks/Business.framework/Resources" "$app/Frameworks/AppleFixture.framework/Resources" "$out/Other.bundle/Contents"
python3 - "$out" <<'PY'
import pathlib,plistlib,sys
out=pathlib.Path(sys.argv[1]); app=out/'IdentityFixture.app'
info={'CFBundleIdentifier':'dev.simrun.identity-fixture','CFBundleName':'IdentityFixture','CFBundlePackageType':'APPL','CFBundleExecutable':'IdentityFixture','CFBundleVersion':'123','DTPlatformName':'iphonesimulator','DTSDKName':'iphonesimulator27.1','CFBundleSupportedPlatforms':['iPhoneSimulator']}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
source=dict(info,CFBundleVersion='999',DTPlatformName='iphoneos',DTSDKName='iphoneos27.1',CFBundleSupportedPlatforms=['iPhoneOS'])
(out/'original.plist').write_bytes(plistlib.dumps(source))
(out/'Other.bundle/Contents/Info.plist').write_bytes(plistlib.dumps(dict(info,CFBundleIdentifier='dev.simrun.other-fixture',CFBundlePackageType='BNDL')))
for name,bundle in [('Business','dev.simrun.business-fixture'),('AppleFixture','com.apple.identity-fixture')]:
 p=app/'Frameworks'/f'{name}.framework'
 (p/'Resources/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':bundle,'CFBundleExecutable':name,'CFBundlePackageType':'FMWK'}))
 (p/'Info.plist').write_bytes((p/'Resources/Info.plist').read_bytes())
PY
cc=(xcrun --sdk macosx clang -arch arm64 -fobjc-arc -O2 -fno-optimize-sibling-calls -Wall -Wextra -Werror)
"${cc[@]}" -dynamiclib "$here/identity.m" -framework Foundation -o "$out/Identity.dylib"
"${cc[@]}" -dynamiclib -DSR_SNAPSHOT=SRFrameworkSnapshot "$here/tests/snapshot.m" -framework Foundation -o "$app/Frameworks/Business.framework/Business"
"${cc[@]}" -dynamiclib -DSR_SNAPSHOT=SRAppleSnapshot "$here/tests/snapshot.m" -framework Foundation -o "$app/Frameworks/AppleFixture.framework/AppleFixture"
"${cc[@]}" -dynamiclib -DSR_SNAPSHOT=SRExternalSnapshot "$here/tests/snapshot.m" -framework Foundation -o "$out/External.dylib"
"${cc[@]}" -dynamiclib -DSR_SNAPSHOT=SRInjectedSnapshot "$here/tests/snapshot.m" -framework Foundation -o "$app/Frameworks/Injected.dylib"
"${cc[@]}" "$here/tests/main.m" "$here/tests/snapshot.m" -framework Foundation -o "$app/Contents/MacOS/IdentityFixture"
for binary in "$out/Identity.dylib" "$app/Frameworks/Business.framework/Business" "$app/Frameworks/AppleFixture.framework/AppleFixture" "$out/External.dylib" "$app/Frameworks/Injected.dylib"; do codesign --force --sign - "$binary"; done
export SIMRUN_DEVICE_IDENTITY_APP_ROOT="$app"
export SIMRUN_DEVICE_IDENTITY_MODEL=iPhone18,1
export SIMRUN_DEVICE_IDENTITY_ORIGINAL_INFO="$out/original.plist"
export SIMULATOR_IDENTITY_FIXTURE=simulator-marker SIMRUN_IDENTITY_FIXTURE=simrun-marker ORDINARY_IDENTITY_FIXTURE=ordinary-value
export SIMRUND_SOCKET=control-marker SIMNS_IDENTITY_FIXTURE=control-marker SIMAPP_IDENTITY_FIXTURE=control-marker
export DYLD_INSERT_LIBRARIES="$out/Identity.dylib:$app/Frameworks/Injected.dylib"
SIMRUN_DEVICE_IDENTITY=1 "$app/Contents/MacOS/IdentityFixture" "$out" enabled > "$out/enabled.json"
SIMRUN_DEVICE_IDENTITY=0 "$app/Contents/MacOS/IdentityFixture" "$out" disabled > "$out/disabled.json"
SIMRUN_DEVICE_IDENTITY=1 SIMRUN_DEVICE_IDENTITY_APP_ROOT="$out/Other.bundle" "$app/Contents/MacOS/IdentityFixture" "$out" disabled > "$out/wrong-root.json"
SIMRUN_DEVICE_IDENTITY=1 SIMRUN_DEVICE_IDENTITY_ORIGINAL_INFO="$app/Contents/Info.plist" "$app/Contents/MacOS/IdentityFixture" "$out" disabled > "$out/wrong-info.json"
SIMRUN_DEVICE_IDENTITY=1 SIMRUN_DEVICE_IDENTITY_MODEL= "$app/Contents/MacOS/IdentityFixture" "$out" disabled > "$out/missing-model.json"
echo "$out"
