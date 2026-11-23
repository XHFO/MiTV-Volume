# Third-party components

## Proxy Audio Device

Upstream: https://github.com/briankendall/proxy-audio-device (baseline d3d8c8c).

The modified source is retained under `Driver/`. Its upstream Unlicense is preserved in `Driver/LICENSE`; per-file notices, including notices in the Apple utility sources, remain in place. Only the audio driver is included in the application bundle.

## Android Debug Bridge

Upstream: https://android.googlesource.com/platform/packages/modules/adb/ and https://developer.android.com/tools/releases/platform-tools.

The universal macOS executable is in `Resources/ADB/adb`. The accompanying license and third-party notices are preserved in `Resources/ADB/NOTICE.txt` and copied to `Contents/Resources/ADB-NOTICE.txt` in the application bundle. No ADB private key or device authorization is distributed.

## Protocol reference

The LAN volume protocol was studied from https://github.com/pengchujin/MiTV-Remote (reference bacb9f0). The Swift volume client in this repository is independently implemented; that project's application is not bundled.

These notices describe the third-party components and do not replace their original license terms or grant a new license to other project files.
