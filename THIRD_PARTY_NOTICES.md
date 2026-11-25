# Third-party components

## Proxy Audio Device

Upstream: https://github.com/briankendall/proxy-audio-device (baseline d3d8c8c).

The modified source is retained under `Driver/`. Its upstream Unlicense is preserved in `Driver/LICENSE`; per-file notices, including notices in the Apple utility sources, remain in place. Only the audio driver is included in the application bundle.

## Protocol reference

The LAN volume protocol was studied from https://github.com/pengchujin/MiTV-Remote (reference bacb9f0). The Swift volume client in this repository is independently implemented; that project's application is not bundled.

Television input-source status is read from the separately installed [XHFO/XHFlow](https://github.com/XHFO/XHFlow) app on the TV over its LAN configuration API. XHFlow itself is not bundled.

## Apple system artwork (device/interface images)

The device/interface images are rendered from macOS SF Symbols and native AppKit template
images, using AppKit and iconutil. Apple system artwork remains subject to the applicable
Apple license and usage restrictions, including those for SF Symbols:
https://developer.apple.com/sf-symbols/
They are not included under this repository's software license. Apple hardware symbols are
used only as user-selected device representations, never as this app's logo.
The purple waveform app icon is an original vector composition, authored in Icon Composer.

These notices describe the third-party components and do not replace their original license terms or grant a new license to other project files.
