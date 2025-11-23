// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HSBCPartnerSDK",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "HSBCPartnerSDKCore",
            targets: ["HSBCPartnerSDKCore"]
        ),
        .library(
            name: "HSBCPlugins",
            targets: ["HSBCPlugins"]
        )
    ],
    targets: [
        .target(
            name: "HSBCPartnerSDKCore",
            resources: [
                .process("Resources/ao_test.html"),
                .process("PrivacyInfo.xcprivacy")
            ]
        ),
        .target(
            name: "HSBCPlugins",
            dependencies: [
                "HSBCPartnerSDKCore"
            ]
        ),
        .testTarget(
            name: "HSBCPartnerSDKCoreTests",
            dependencies: [
                "HSBCPartnerSDKCore"
            ]
        )
    ]
)
