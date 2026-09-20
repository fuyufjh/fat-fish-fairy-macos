// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FatFishFairy",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "FatFishFairy", targets: ["FatFishFairy"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .executableTarget(name: "FatFishFairy", dependencies: ["CSQLite"], resources: [.copy("Resources/Themes"), .copy("Resources/SystemPrompt.md"), .copy("Resources/AppIcon.png")])
    ],
    swiftLanguageModes: [.v5]
)
