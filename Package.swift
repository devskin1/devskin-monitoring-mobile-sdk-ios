// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "DevSkinMobileSDK",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "DevSkinMobileSDK",
            targets: ["DevSkinMobileSDK"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DevSkinMobileSDK",
            dependencies: [],
            path: ".",
            exclude: ["DevSkinMobileSDK.podspec", "LICENSE", "README.md"],
            sources: [
                "DevSkinSDK.swift",
                "Collectors",
                "Transport",
                "SessionRecording"
            ]
        ),
        .testTarget(
            name: "DevSkinMobileSDKTests",
            dependencies: ["DevSkinMobileSDK"],
            path: "Tests"
        ),
    ]
)
