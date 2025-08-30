// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PuntoPunto",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "PuntoPunto",
            targets: ["PuntoPunto"])
    ],
    targets: [
        .executableTarget(
            name: "PuntoPunto",
            dependencies: [],
            path: "Sources",
            resources: [
                .copy("../Assets")
            ]
        )
    ]
)
