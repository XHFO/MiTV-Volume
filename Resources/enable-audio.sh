#!/bin/bash
# Called only by the application's macOS administrator-authorization request.
set -euo pipefail
[ "$EUID" -eq 0 ] || { echo '需要系统管理员授权。' >&2; exit 1; }
[ "$#" -eq 1 ] || exit 2
source_bundle="$1"
parent=/Library/Audio/Plug-Ins/HAL
target="$parent/MiTVVolumeDriver.driver"
for path in /Library/Audio /Library/Audio/Plug-Ins "$parent" "$target"; do
    [ ! -L "$path" ] || { echo '音频组件路径异常，未进行更改。' >&2; exit 3; }
done
/usr/bin/codesign --verify --strict --all-architectures "$source_bundle"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_bundle/Contents/Info.plist")" = local.xh.MiTVVolumeDriver ] || exit 4
/bin/mkdir -p "$parent"
staging=$(/usr/bin/mktemp -d "$parent/.MiTVVolume.XXXXXX")
cleanup() {
    if [ -d "$staging/previous" ] && [ ! -e "$target" ]; then /bin/mv "$staging/previous" "$target"; fi
    /bin/rm -rf "$staging"
}
trap cleanup EXIT
/usr/bin/ditto --norsrc --noextattr "$source_bundle" "$staging/new"
[ -z "$(/usr/bin/find "$staging/new" -type l -print -quit)" ] || exit 5
/usr/bin/codesign --verify --strict --all-architectures "$staging/new"
/usr/sbin/chown -R root:wheel "$staging/new"
/bin/chmod -R a+rX,go-w "$staging/new"
if [ -e "$target" ]; then /bin/mv "$target" "$staging/previous"; fi
/bin/mv "$staging/new" "$target"
# coreaudiod is managed by launchd and automatically returns after termination.
# The app waits for the actual Core Audio device before continuing setup.
/usr/bin/killall -TERM coreaudiod >/dev/null 2>&1 || true
