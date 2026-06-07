// swift-tools-version: 6.2

import PackageDescription

// AgentBridge — local package grafting Open Island's agent bridge into AllNotch.
//
// The internal module name `OpenIslandCore` is intentionally preserved (mirroring
// how Atoll keeps its internal `DynamicIsland` module): only user-visible surfaces
// are de-branded. The agent hook/setup CLIs are exposed as `AgentHooks`/`AgentSetup`.
let package = Package(
    name: "AgentBridge",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "OpenIslandCore",
            targets: ["OpenIslandCore"]
        ),
        .executable(
            name: "AgentHooks",
            targets: ["AgentHooks"]
        ),
        .executable(
            name: "AgentSetup",
            targets: ["AgentSetup"]
        ),
    ],
    targets: [
        .target(
            name: "OpenIslandCore",
            resources: [
                .copy("Resources/open-island-opencode.js"),
            ]
        ),
        .executableTarget(
            name: "AgentHooks",
            dependencies: ["OpenIslandCore"]
        ),
        .executableTarget(
            name: "AgentSetup",
            dependencies: ["OpenIslandCore"]
        ),
    ]
)
