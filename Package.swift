// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FatFishFairy",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "FatFishFairy", targets: ["FatFishFairy"])],
    targets: [
        .executableTarget(name: "FatFishFairy")
    ],
    swiftLanguageModes: [.v5]
)
