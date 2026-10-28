// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AdsKit",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "AdsKit", targets: ["AdsKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads",
                 from: "13.0.0"),
        .package(url: "https://github.com/googleads/swift-package-manager-google-user-messaging-platform",
                 from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "AdsKit",
            dependencies: [
                .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
                .product(name: "GoogleUserMessagingPlatform",
                         package: "swift-package-manager-google-user-messaging-platform"),
            ]
        ),
    ]
)
