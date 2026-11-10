// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SaveMoneyCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "SaveMoneyCore", targets: ["SaveMoneyCore"])],
    targets: [
        .target(name: "SaveMoneyCore", path: "App", exclude: ["SaveMoneyApp.swift", "Info.plist", "Views", "Tests", "Assets.xcassets"], sources: ["Models", "Services"]),
        .testTarget(name: "SaveMoneyCoreTests", dependencies: ["SaveMoneyCore"], path: "App/Tests", exclude: ["SmokeTests.swift"], resources: [.copy("Fixtures")])
    ]
)
