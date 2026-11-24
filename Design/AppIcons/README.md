# App icon proposals

Four original vector compositions, rendered with Apple Icon Composer, Design Generation 27.

- A-GlassSlider: glass sliders
- B-Resonance: audio waveform
- C-SyncLink: linked endpoints
- D-VolumeDial: volume dial

Each `.icon` is an editable Icon Composer document. No SF Symbol is used as the app brand.
The approved icon uses B’s waveform with C’s purple palette and lives in
Resources/AppIcon.icon. The following command can preview an alternative:

```sh
APP_ICON_DOCUMENT="$PWD/Design/AppIcons/D-VolumeDial.icon" scripts/build.sh
```

Xcode actool compiles Assets.car and a legacy ICNS fallback. Resources/AppIcon.icon is used by default.

Device/interface symbols are separate, in Resources/DeviceIcons. They are rendered using
Apple AppKit SF Symbols and iconutil. Regenerate on macOS with:

```sh
swift scripts/render-device-icons.swift "$PWD"
```

Core Audio exposes the selected resource through kAudioDevicePropertyIcon and emits
category-change notifications. Control Center chooses its own category artwork rather
than rendering the resource URL directly.

The current menu offers seven appearances verified on macOS 27.0.1: display, generic
speaker, headphones, TV, Bluetooth, AirPlay, and host Mac. The host Mac silhouette depends
on the current computer model. Twelve stable resource IDs remain readable for backwards
compatibility; USB, Thunderbolt, and FireWire fall back to a generic speaker in the tested
Control Center and are not offered as new distinct choices. HomePod product silhouettes
and cabinet speakers do not have a reliable mapping in this HAL implementation.

Device and data-source labels both use the user's device name. Changing artwork or
category never derives a new device name from the style label. See README.md and
Tests/DriverTests for the property and name-preservation checks.
