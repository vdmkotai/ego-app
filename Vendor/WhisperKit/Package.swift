// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "WhisperKit", platforms: [.iOS(.v16), .macOS(.v13)], products: [.library(name: "WhisperKit", targets: ["WhisperKit"])], targets: [.target(name: "ArgmaxCore"), .target(name: "WhisperKit", dependencies: ["ArgmaxCore"])], swiftLanguageVersions: [.v5])
