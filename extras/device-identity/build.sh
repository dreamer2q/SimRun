#!/bin/bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
out="${1:-$here/../../build/device-identity}"
mkdir -p "$out"
xcrun --sdk iphonesimulator clang -arch arm64 -mios-simulator-version-min=17.0 \
  -fobjc-arc -O2 -Wall -Wextra -Werror -dynamiclib "$here/identity.m" \
  -framework Foundation -o "$out/SimRunDeviceIdentity.dylib"
codesign --force --sign - "$out/SimRunDeviceIdentity.dylib"
codesign --verify --strict "$out/SimRunDeviceIdentity.dylib"
echo "$out/SimRunDeviceIdentity.dylib"
