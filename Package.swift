// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "SwiftIKEADeskControl",
    platforms: [
       .macOS(.v10_15)
    ],
    products: [
        .executable(name: "IKEADeskControl", targets: ["SwiftIKEADeskControl"]),
    ],
    targets: [
        .target(
            name: "SwiftIKEADeskControl",
            path: "swift/"
        ),
    ]
)
