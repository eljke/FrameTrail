// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FrameTrailCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "FrameTrailCore", targets: ["FrameTrailCore"])],
    targets: [
        .target(name: "FrameTrailCore"),
        .testTarget(name: "FrameTrailCoreTests", dependencies: ["FrameTrailCore"])
    ]
)
