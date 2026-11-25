// Exercise the actual driver's property entry points with a fake HAL host.
#include "../../Driver/proxyAudioDevice/ProxyAudioDevice.cpp"
#include <cassert>
#include <limits>
#include <iostream>
#include <vector>
static std::vector<AudioObjectPropertyAddress> iconChanges;
static int notifications = 0;
static int iconNotifications = 0;
static CFStringRef storedIcon = nullptr;
static CFStringRef storedName = nullptr;
static int nameWrites = 0;
static int sourceNameNotifications = 0;
static OSStatus storeIcon(AudioServerPlugInHostRef, CFStringRef key, CFPropertyListRef value) {
    if (CFEqual(key, CFSTR("deviceName"))) {
        ++nameWrites;
        if (storedName) CFRelease(storedName);
        storedName = CFStringCreateCopy(NULL, (CFStringRef)value);
        return noErr;
    }
    assert(CFEqual(key, CFSTR("deviceIconStyle")));
    if (storedIcon) CFRelease(storedIcon);
    storedIcon = CFStringCreateCopy(NULL, (CFStringRef)value);
    return noErr;
}
static OSStatus changed(AudioServerPlugInHostRef, AudioObjectID object, UInt32 count, const AudioObjectPropertyAddress *addresses) {
    if (object == kObjectID_DataSource_Output_Master && addresses->mSelector == kAudioSelectorControlPropertyItemName) ++sourceNameNotifications;
    if (object == kObjectID_Device) iconChanges.insert(iconChanges.end(), addresses, addresses + count);
    if (addresses->mSelector == kAudioDevicePropertyIcon) ++iconNotifications;
    ++notifications; return noErr;
}
int main(int argc, const char *argv[]) {
    CFBundleRef resourceBundle = nullptr;
    if (argc > 1) {
        CFURLRef bundleURL = CFURLCreateFromFileSystemRepresentation(NULL,
            reinterpret_cast<const UInt8 *>(argv[1]), strlen(argv[1]), true);
        resourceBundle = CFBundleCreate(NULL, bundleURL); CFRelease(bundleURL);
        assert(resourceBundle && CFEqual(CFBundleGetIdentifier(resourceBundle), CFSTR(kPlugIn_BundleID)));
    }
    AudioServerPlugInHostInterface host = {};
    host.PropertiesChanged = changed;
    ProxyAudioDevice device;
    device.gPlugIn_Host = &host;
    AudioObjectPropertyAddress snapshot = {kMiTVVolumeState, kAudioObjectPropertyScopeGlobal, 0};
    auto read = [&]() {
        MiTVVolumeState state = {};
        CFPropertyListRef data = nullptr;
        UInt32 size = sizeof(data);
        assert(device.GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 0,
            &snapshot, 0, nullptr, sizeof(data), &size, &data) == noErr);
        assert(size == sizeof(data));
        assert(CFGetTypeID(data) == CFDataGetTypeID());
        assert(CFDataGetLength(static_cast<CFDataRef>(data)) == 16);
        CFDataGetBytes(static_cast<CFDataRef>(data), CFRangeMake(0, 16), reinterpret_cast<UInt8 *>(&state));
        CFRelease(data); return state;
    };
    auto confirm = [&](UInt64 revision, Float32 scalar) {
        MiTVVolumeState value = {revision, scalar, 0};
        CFPropertyListRef data = CFDataCreate(NULL, reinterpret_cast<const UInt8 *>(&value), sizeof(value));
        auto status = device.SetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 0,
            &snapshot, 0, nullptr, sizeof(data), &data);
        CFRelease(data); return status;
    };
    auto command = [&](AudioObjectID channel, Float32 scalar) {
        AudioObjectPropertyAddress address = {kAudioLevelControlPropertyScalarValue, kAudioObjectPropertyScopeGlobal, 0};
        return device.SetPropertyData(gAudioServerPlugInDriverRef, channel, 0, &address, 0, nullptr, sizeof(scalar), &scalar);
    };
    AudioObjectPropertyAddress infoAddress = {kAudioObjectPropertyCustomPropertyInfoList, kAudioObjectPropertyScopeGlobal, 0};
    AudioServerPlugInCustomPropertyInfo info = {};
    UInt32 infoSize = sizeof(info);
    assert(device.GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 0, &infoAddress,
        0, nullptr, sizeof(info), &infoSize, &info) == noErr);
    assert(info.mSelector == kMiTVVolumeState);
    assert(info.mPropertyDataType == kAudioServerPlugInCustomPropertyDataTypeCFPropertyList);
    assert(read().revision == 0);
    assert(confirm(0, .2f) == noErr);
    assert(read().revision == 0 && read().scalar == .2f);
    assert(device.gVolume_Output_L_Value == .2f && device.gVolume_Output_R_Value == .2f);
    assert(notifications == 2);
    assert(command(kObjectID_Volume_Output_L, .5f) == noErr);
    auto first = read(); assert(first.revision == 1 && first.scalar == .5f);
    assert(command(kObjectID_Volume_Output_R, .8f) == noErr);
    assert(confirm(first.revision, .5f) == kAudioHardwareIllegalOperationError);
    auto latest = read(); assert(latest.revision == 2 && latest.scalar == .8f);
    assert(confirm(latest.revision, .8f) == noErr);
    assert(command(kObjectID_Volume_Output_L, .8f) == noErr);
    assert(read().revision == latest.revision); // echoed same value cannot create a command
    assert(confirm(latest.revision, std::numeric_limits<float>::quiet_NaN()) != noErr);
    assert(command(kObjectID_Volume_Output_L, std::numeric_limits<float>::quiet_NaN()) != noErr);
    assert(confirm(latest.revision, 1.1f) != noErr);
    AudioObjectPropertyAddress mute = {kAudioBooleanControlPropertyValue, kAudioObjectPropertyScopeGlobal, 0};
    UInt32 value = 1;
    assert(device.SetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Mute_Output_Master, 0,
        &mute, 0, nullptr, sizeof(value), &value) == noErr);
    assert(read().scalar == 0 && read().revision == 3);
    assert(confirm(3, 0) == noErr);
    value = 0;
    assert(device.SetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Mute_Output_Master, 0,
        &mute, 0, nullptr, sizeof(value), &value) == noErr);
    assert(read().scalar == .8f && read().revision == 4);
    host.WriteToStorage = storeIcon;
    device.audioOutputQueue = dispatch_queue_create("test.icons", DISPATCH_QUEUE_SERIAL);
    ProxyAudioDevice::ConfigType action = ProxyAudioDevice::ConfigType::none;
    CFStringRef parsed = nullptr;
    device.parseConfigurationString(CFSTR("deviceIconStyle=3"), action, parsed);
    assert(action == ProxyAudioDevice::ConfigType::deviceIconStyle && CFEqual(parsed, CFSTR("3")));
    CFRelease(parsed);
    const CFStringRef customName = CFSTR("我的音箱 🎵 = 工作室");
    device.setConfigurationValue(ProxyAudioDevice::ConfigType::deviceName, customName);
    dispatch_sync(device.audioOutputQueue, ^{});
    assert(nameWrites == 1 && CFEqual(storedName, customName));
    iconChanges.clear();
    const auto volumeBeforeIcons = read();
    device.outputDeviceUID = CFStringCreateCopy(NULL, CFSTR("test-physical-output"));
    for (UInt32 i = 0; i < 12; ++i) {
        CFStringRef choice = CFStringCreateWithFormat(NULL, NULL, CFSTR("%u"), i);
        CFStringRef command = CFStringCreateWithFormat(NULL, NULL, CFSTR("deviceIconStyle=%u"), i);
        action = ProxyAudioDevice::ConfigType::none;
        parsed = nullptr;
        device.parseConfigurationString(command, action, parsed);
        assert(action == ProxyAudioDevice::ConfigType::deviceIconStyle && CFEqual(parsed, choice));
        device.setConfigurationValue(action, parsed);
        CFRelease(parsed); CFRelease(command);
        dispatch_sync(device.audioOutputQueue, ^{});
        assert(device.deviceIconStyle == i);
        AudioObjectPropertyAddress terminal = {kAudioStreamPropertyTerminalType, kAudioObjectPropertyScopeGlobal, 0};
        UInt32 kind = 0, kindSize = sizeof(kind);
        assert(device.GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Stream_Output, 0,
            &terminal, 0, nullptr, sizeof(kind), &kindSize, &kind) == noErr);
        const UInt32 kinds[] = {kAudioStreamTerminalTypeDisplayPort, kAudioStreamTerminalTypeSpeaker,
            kAudioStreamTerminalTypeHeadphones, kAudioStreamTerminalTypeSpeaker,
            kAudioStreamTerminalTypeHDMI, kAudioStreamTerminalTypeSpeaker,
            kAudioStreamTerminalTypeSpeaker, kAudioStreamTerminalTypeSpeaker,
            kAudioStreamTerminalTypeSpeaker, kAudioStreamTerminalTypeSpeaker,
            kAudioStreamTerminalTypeSpeaker, kAudioStreamTerminalTypeSpeaker};
        assert(kind == kinds[i]);
        AudioObjectPropertyAddress transport = {kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal, 0};
        assert(device.GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 0,
            &transport, 0, nullptr, sizeof(kind), &kindSize, &kind) == noErr);
        const UInt32 transports[] = {kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeVirtual,
            kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeVirtual,
            kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeVirtual,
            kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeBluetooth,
            kAudioDeviceTransportTypeAirPlay, kAudioDeviceTransportTypeThunderbolt,
            kAudioDeviceTransportTypeFireWire, kAudioDeviceTransportTypeVirtual};
        assert(kind == transports[i]);
        transport.mScope = kAudioObjectPropertyScopeOutput;
        assert(device.GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 0,
            &transport, 0, nullptr, sizeof(kind), &kindSize, &kind) == noErr && kind == transports[i]);
        AudioObjectPropertyAddress source = {kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeOutput, 0};
        assert(device.HasProperty(gAudioServerPlugInDriverRef, kObjectID_Device, 0, &source));
        assert(device.GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 0,
            &source, 0, nullptr, sizeof(kind), &kindSize, &kind) == noErr);
        assert(kind == (i == 2 ? 'hdpn' : 'ispk'));
        Boolean settable = true;
        assert(device.IsPropertySettable(gAudioServerPlugInDriverRef, kObjectID_Device, 0, &source, &settable) == noErr && !settable);
        assert(device.GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 0,
            &source, 0, nullptr, 1, &kindSize, &kind) == kAudioHardwareBadPropertySizeError);
        source.mScope = kAudioObjectPropertyScopeGlobal;
        source.mSelector = kAudioSelectorControlPropertyCurrentItem;
        assert(device.GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_DataSource_Output_Master, 0,
            &source, 0, nullptr, sizeof(kind), &kindSize, &kind) == noErr);
        assert(kind == (i == 2 ? 'hdpn' : 'ispk'));
        source.mSelector = kAudioSelectorControlPropertyItemName;
        CFStringRef sourceName = nullptr; UInt32 nameSize = sizeof(sourceName);
        assert(device.GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_DataSource_Output_Master, 0,
            &source, sizeof(kind), &kind, sizeof(sourceName), &nameSize, &sourceName) == noErr);
        assert(CFEqual(sourceName, customName));
        CFRelease(sourceName);
        source.mSelector = kAudioDevicePropertyDataSource;
        source.mScope = kAudioObjectPropertyScopeInput;
        assert(!device.HasProperty(gAudioServerPlugInDriverRef, kObjectID_Device, 0, &source));
        if (i > 0) {
            bool outputTransport = false, outputSource = false;
            for (auto address : iconChanges) {
                if (address.mScope != kAudioObjectPropertyScopeOutput) continue;
                outputTransport |= address.mSelector == kAudioDevicePropertyTransportType;
                outputSource |= address.mSelector == kAudioDevicePropertyDataSource;
            }
            assert(outputTransport && outputSource);
        }
        // Class changes must never rename or reroute the user's device or issue volume commands.
        for (auto address : iconChanges) assert(address.mSelector != kAudioObjectPropertyName);
        assert(CFEqual(device.deviceName, customName) && CFEqual(storedName, customName) && nameWrites == 1);
        assert(CFEqual(device.outputDeviceUID, CFSTR("test-physical-output")));
        assert(read().revision == volumeBeforeIcons.revision && read().scalar == volumeBeforeIcons.scalar);
        AudioObjectPropertyAddress nameAddress = {kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal, 0};
        CFStringRef liveName = nullptr; UInt32 liveNameSize = sizeof(liveName);
        assert(device.GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 0,
            &nameAddress, 0, nullptr, sizeof(liveName), &liveNameSize, &liveName) == noErr);
        assert(CFEqual(liveName, customName)); CFRelease(liveName);
        iconChanges.clear();
        CFStringRef actual = device.copyConfigurationValue(ProxyAudioDevice::ConfigType::deviceIconStyle);
        assert(CFEqual(actual, choice)); CFRelease(actual);
        if (i > 0) assert(CFEqual(storedIcon, choice));
        CFRelease(choice);
        if (resourceBundle) {
            AudioObjectPropertyAddress icon = {kAudioDevicePropertyIcon, kAudioObjectPropertyScopeGlobal, 0};
            CFURLRef iconURL = nullptr; UInt32 bytes = sizeof(iconURL);
            assert(device.GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_Device, 0,
                &icon, 0, nullptr, sizeof(iconURL), &bytes, &iconURL) == noErr);
            assert(iconURL && CFURLResourceIsReachable(iconURL, nullptr));
            const char *names[] = {"Device-display.icns", "Device-speaker.icns", "Device-headphones.icns",
                "Device-homepod.icns", "Device-appletv.icns", "Device-homepodmini.icns",
                "Device-usb.icns", "Device-bluetooth.icns", "Device-airplay.icns",
                "Device-thunderbolt.icns", "Device-firewire.icns", "Device-mac.icns"};
            CFStringRef last = CFURLCopyLastPathComponent(iconURL);
            CFStringRef expected = CFStringCreateWithCString(NULL, names[i], kCFStringEncodingUTF8);
            assert(CFEqual(last, expected)); CFRelease(expected); CFRelease(last); CFRelease(iconURL);
        }
    }
    assert(iconNotifications == 11);
    for (auto invalid : {CFSTR("12"), CFSTR("99"), CFSTR("01"), CFSTR("+1"), CFSTR("1 "), CFSTR("1x"), CFSTR("-1"), CFSTR("../evil"), CFSTR("abc"), CFSTR("")}) {
        device.setDeviceIconStyle(invalid);
    }
    device.setDeviceIconStyle(CFSTR("11"));
    dispatch_sync(device.audioOutputQueue, ^{});
    assert(device.deviceIconStyle == 11 && iconNotifications == 11);
    assert(nameWrites == 1 && CFEqual(storedName, customName) && sourceNameNotifications == 1);
    device.setDeviceName(CFSTR("用户改名后的音箱"));
    dispatch_sync(device.audioOutputQueue, ^{});
    assert(nameWrites == 2 && sourceNameNotifications == 2);
    AudioObjectPropertyAddress sourceLabel = {kAudioSelectorControlPropertyItemName, kAudioObjectPropertyScopeGlobal, 0};
    UInt32 item = 'ispk', labelSize = sizeof(CFStringRef); CFStringRef label = nullptr;
    assert(device.GetPropertyData(gAudioServerPlugInDriverRef, kObjectID_DataSource_Output_Master, 0,
        &sourceLabel, sizeof(item), &item, sizeof(label), &labelSize, &label) == noErr);
    assert(CFEqual(label, CFSTR("用户改名后的音箱"))); CFRelease(label);
    CFRelease(storedName);
    CFRelease(storedIcon);
    if (resourceBundle) CFRelease(resourceBundle);
    std::cout << "Device icons passed: 12 choices, persistence, notifications, strict whitelist; custom name, output and volume preserved.\n";
    std::cout << "Driver property tests passed: CAS, stereo feedback, notification, echo, invalid values, mute restore.\n";
}
