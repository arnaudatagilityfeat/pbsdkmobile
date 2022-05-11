// swift-tools-version:5.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PBSKurentoSDK",
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "PBSKurentoSDK",
            targets: ["PBSKurentoSDK"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(name: "WebRTC", url: "https://github.com/alexpiezo/WebRTC.git", .upToNextMajor(from: "1.1.29507")),
        .package(name: "PMKFoundation", url: "https://github.com/PromiseKit/Foundation.git", .upToNextMajor(from: "3.4.0"))
        
//        .package(url: "https://github.com/livekit/WebRTC-swift.git", .upToNextMajor(from: "1.91.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "PBSKurentoSDK",
            dependencies: [.product(name: "WebRTC", package: "WebRTC"), .product(name: "PMKFoundation", package: "PMKFoundation")]),
        .testTarget(
            name: "PBSKurentoSDKTests",
            dependencies: ["PBSKurentoSDK"]),
    ]
)

