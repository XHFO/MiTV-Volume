#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="${BUILD_DIR:-${TMPDIR:-/tmp}/MiTVVolumeBuild}"
mkdir -p "$build"
xcrun clang++ -std=c++11 -fblocks -Wno-deprecated-declarations -Wno-inconsistent-missing-override \
  -mmacosx-version-min=13.0 -I"$root/Driver/proxyAudioDevice" -I"$root/Driver/shared" -I"$root/Driver/proxyAudioDevice/PublicUtility" \
  "$root/Tests/DriverTests/main.cpp" "$root/Driver/shared/AudioDevice.cpp" \
  "$root/Driver/proxyAudioDevice/AudioRingBuffer.cpp" "$root/Driver/proxyAudioDevice/utilities.cpp" \
  "$root"/Driver/proxyAudioDevice/PublicUtility/*.cpp \
  -framework CoreAudio -framework CoreFoundation -framework CoreServices -framework IOKit -framework AppKit \
  -o "$build/driver-tests"
"$build/driver-tests"
