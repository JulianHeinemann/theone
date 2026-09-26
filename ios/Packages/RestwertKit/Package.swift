// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RestwertKit",
    defaultLocalization: "de",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RestwertKit", targets: ["RestwertKit"]),
    ],
    targets: [
        .target(name: "RestwertKit"),
        .testTarget(name: "RestwertKitTests", dependencies: ["RestwertKit"]),
    ],
    swiftLanguageModes: [.v6]
)
