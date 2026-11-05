// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "CompanionCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v13)],
    products: [.library(name: "CompanionCore", targets: ["CompanionCore"])],
    targets: [
        .target(name: "CompanionCore", path: "Shared", exclude: ["Connectivity.swift", "CompanionStore.swift", "Assets.xcassets"], sources: ["Core.swift", "RemoteSigning.swift", "RemoteRelay.swift", "RemoteAPI.swift"]),
        .testTarget(name: "CompanionCoreTests", dependencies: ["CompanionCore"])
    ]
)
