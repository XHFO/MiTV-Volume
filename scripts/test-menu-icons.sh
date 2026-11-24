#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="${BUILD_DIR:-${TMPDIR:-/tmp}/MiTVVolumeMenuTests}"
mkdir -p "$build"
export CLANG_MODULE_CACHE_PATH="$build/module-cache"
xcrun swiftc -parse-as-library "$root/Sources/MiTVVolume/DeviceIconStyle.swift" \
  "$root/Tests/MenuIcons/main.swift" -o "$build/menu-icon-tests"
"$build/menu-icon-tests"
