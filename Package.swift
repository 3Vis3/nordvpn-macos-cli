// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "nordvpn-macos-cli",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "nordvpn-macos",
            targets: ["NordVPNMacOSCLI"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "NordVPNMacOSCLI"
        ),
    ]
)
