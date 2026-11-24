#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build="${BUILD_DIR:-${TMPDIR:-/tmp}/MiTVVolumeBuild}"
dist="${DIST_DIR:-$root/dist}"
mkdir -p "$build" "$dist"
export CLANG_MODULE_CACHE_PATH="$build/module-cache"
export SWIFT_MODULECACHE_PATH="$build/module-cache"
xcodebuild -project "$root/Driver/proxyAudioDevice.xcodeproj" -target ProxyAudioDevice \
  -configuration Release CONFIGURATION_BUILD_DIR="$build/driver" OBJROOT="$build/driver-obj" \
  SHARED_PRECOMPS_DIR="$build/precompiled" MODULE_CACHE_DIR="$build/module-cache" \
  CODE_SIGNING_ALLOWED=NO PRODUCT_BUNDLE_IDENTIFIER=local.xh.MiTVVolumeDriver \
  PRODUCT_NAME=MiTVVolumeDriver MARKETING_VERSION=0.3.5 CURRENT_PROJECT_VERSION=9 \
  MACOSX_DEPLOYMENT_TARGET=13.0 ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
swift build --disable-sandbox --package-path "$root" --scratch-path "$build/swift" \
  -c release --arch arm64 --arch x86_64
bin="$(swift build --disable-sandbox --package-path "$root" --scratch-path "$build/swift" -c release --arch arm64 --arch x86_64 --show-bin-path)"
stage="$(mktemp -d "${TMPDIR:-/tmp}/MiTVVolume-stage.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
chmod 755 "$stage"
app="$stage/Applications/MiTV Volume.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/MiTVVolume" "$app/Contents/MacOS/MiTVVolume"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.xh.MiTVVolume</string>
<key>CFBundleExecutable</key><string>MiTVVolume</string>
<key>CFBundleName</key><string>小米电视音量</string>
<key>CFBundleDisplayName</key><string>小米电视音量</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.6.0</string>
<key>CFBundleVersion</key><string>15</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocalNetworkUsageDescription</key><string>读取并同步你指定的小米电视音量。</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
# A reviewed Icon Composer document can be selected at build time.
icon_document="${APP_ICON_DOCUMENT:-$root/Resources/AppIcon.icon}"
if [ -d "$icon_document" ]; then
  icon_name="$(basename "$icon_document" .icon)"
  xcrun actool "$icon_document" --compile "$app/Contents/Resources" \
    --platform macosx --target-device mac --minimum-deployment-target 13.0 \
    --app-icon "$icon_name" --output-partial-info-plist "$stage/icon-info.plist"
  /usr/libexec/PlistBuddy -c "Merge $stage/icon-info.plist" "$app/Contents/Info.plist"
fi
ditto --norsrc --noextattr "$build/driver/MiTVVolumeDriver.driver" "$app/Contents/Resources/MiTVVolumeDriver.driver"
cp "$root/Resources/enable-audio.sh" "$app/Contents/Resources/enable-audio.sh"
chmod 644 "$app/Contents/Resources/enable-audio.sh"
cp "$root/Resources/ADB/adb" "$app/Contents/Resources/adb"
cp "$root/Resources/ADB/NOTICE.txt" "$app/Contents/Resources/ADB-NOTICE.txt"
chmod 755 "$app/Contents/Resources/adb"
# Remove build-machine paths from debug symbols before signing public artifacts.
xcrun strip -S "$app/Contents/MacOS/MiTVVolume"
xcrun strip -S "$app/Contents/Resources/MiTVVolumeDriver.driver/Contents/MacOS/MiTVVolumeDriver"
codesign --force --sign - "$app/Contents/Resources/adb"
codesign --force --sign - "$app/Contents/Resources/MiTVVolumeDriver.driver"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
if [ -n "${QA_APP_DIR:-}" ]; then ditto --norsrc --noextattr "$app" "$QA_APP_DIR/MiTV Volume.app"; fi
# The only downloadable item is one self-contained application. No separate installer.
ditto -c -k --norsrc --noextattr --keepParent "$app" "$dist/MiTV-Volume-0.6.0.zip"
printf 'Built: %s\n' "$dist/MiTV-Volume-0.6.0.zip"
