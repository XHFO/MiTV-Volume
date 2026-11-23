# Bundled ADB

Android SDK Platform-Tools adb, universal arm64/x86_64 executable, redistributed with the accompanying NOTICE.txt. Official upstream: https://developer.android.com/tools/releases/platform-tools and https://android.googlesource.com/platform/packages/modules/adb/.

The application uses a dedicated local server on port 5047, reads only `dumpsys tv_input`, and does not install a television application or change its input. Runtime keys are stored in the application's Application Support directory; existing local ~/.android/adbkey authorization can be reused through ADB_VENDOR_KEYS. No private key is included in this project or release.
