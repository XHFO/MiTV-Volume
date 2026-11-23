// Exercise the actual driver's property entry points with a fake HAL host.
#include "../../Driver/proxyAudioDevice/ProxyAudioDevice.cpp"
#include <cassert>
#include <limits>
#include <iostream>
static int notifications = 0;
static OSStatus changed(AudioServerPlugInHostRef, AudioObjectID, UInt32, const AudioObjectPropertyAddress *) {
    ++notifications; return noErr;
}
int main() {
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
    std::cout << "Driver property tests passed: CAS, stereo feedback, notification, echo, invalid values, mute restore.\n";
}
