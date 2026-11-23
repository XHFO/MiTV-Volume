// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MiTVVolume", platforms: [.macOS(.v13)], products: [
    .executable(name: "MiTVVolume", targets: ["MiTVVolume"])
], targets: [
    .target(name: "VolumeCore"),
    .executableTarget(name: "MiTVVolume", dependencies: ["VolumeCore"]),
    .testTarget(name: "VolumeCoreTests", dependencies: ["VolumeCore"])
])
