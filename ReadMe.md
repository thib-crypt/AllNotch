<p align="center">
  <img src="DynamicIsland/Assets.xcassets/AppIcon.appiconset/1024.png" alt="AllNotch icon" width="120">
</p>

<h1 align="center">AllNotch</h1>

<p align="center">
  Your MacBook notch, elevated.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.6%2B-blue?logo=apple&logoColor=white" alt="macOS 14.6+">
  <img src="https://img.shields.io/badge/Swift-5.9-FA7343?logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/License-GPL%20v3-green" alt="GPL v3">
  <img src="https://img.shields.io/badge/version-0.1%20Notch%20Zero-lightgrey" alt="v0.1 Notch Zero">
</p>

---

**AllNotch** is a native macOS app that turns the MacBook notch into an all-in-one control surface — media controls, system stats, live AI agent sessions, and token-usage / cost tracking, without juggling several separate apps.

> **v0.1 "Notch Zero"** — Early release. The full notch UI/UX shell is functional. The Agents and Usage tabs are actively being built.

---

## Features

| Feature | Status |
|---------|--------|
| 🎵 Now Playing — Apple Music, Spotify, Amazon Music | ✅ Ready |
| 🔋 Battery & system stats HUD | ✅ Ready |
| 📋 Clipboard shelf | ✅ Ready |
| ⏱ Timers & lock-screen widgets | ✅ Ready |
| 🗓 Calendar & weather on lock screen | ✅ Ready |
| 🎨 Idle animations & custom notch styles | ✅ Ready |
| 🤖 Live AI agent sessions (Claude, Codex, Cursor, Gemini…) | 🚧 In progress |
| 💰 Token usage & cost tracking | 🚧 In progress |
| 🧩 Plugin architecture | 🚧 In progress |

---

## Screenshots

<p align="center">
  <img src=".github/assets/Non-minimalistic-v1.2.gif" width="380" alt="Notch expanded view">
  <img src=".github/assets/Minimalistic-v1.2.gif" width="380" alt="Minimalistic mode">
</p>
<p align="center">
  <img src=".github/assets/Calendar-v1.2.gif" width="380" alt="Calendar widget">
  <img src=".github/assets/Timer-v1.2.gif" width="380" alt="Timer">
</p>

---

## Requirements

- **macOS 14.6+** (macOS 15 recommended)
- **Xcode 15+** with Swift 5.9 toolchain
- A MacBook with a notch (required for full-feature testing)

---

## Build & Run

```bash
git clone https://github.com/thib-crypt/AllNotch.git
cd AllNotch
open AllNotch.xcodeproj
```

Then in Xcode:
- Select your Mac as the destination
- Build & run the **AllNotch** scheme (`⌘R`)
- Grant requested permissions (calendar, location, Bluetooth…)

Swift Package dependencies resolve automatically on first build.

### Ad-hoc signing (no Apple Developer account needed)

```bash
xcodebuild -scheme AllNotch -configuration Debug \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build
```

---

## Architecture

```
AllNotch/
├── DynamicIsland/           # Main app target (Swift/SwiftUI)
│   ├── components/          # UI views — Notch, Settings, Agents, Shelf…
│   ├── models/              # State, defaults, constants
│   ├── services/            # AgentBridgeController, enrollment…
│   ├── managers/            # System integrations (battery, volume, OSD…)
│   └── Plugins/             # Plugin host + core plugin protocols
└── Packages/
    └── AgentBridge/         # Local SPM package — OpenIslandCore bridge
        └── Sources/
            ├── OpenIslandCore/    # Agent sessions, hooks, usage tracking
            ├── AgentHooks/        # CLI hook runner
            └── AgentSetup/        # Setup CLI
```

The **Plugin** layer decouples optional features from the core; adding a new feature is a single entry in `allPlugins`.

---

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

1. Fork the repo and create a feature branch
2. Make your changes following Swift API Design Guidelines
3. Open a pull request against `main` with a clear description

---

## Credits & License

AllNotch is a **fork of [Atoll](https://github.com/Ebullioscopic/Atoll)** and integrates code from:

| Project | Role | License |
|---------|------|---------|
| [Atoll](https://github.com/Ebullioscopic/Atoll) | Notch UI/UX, media, stats, animations | GPL v3 |
| [Open Island](https://github.com/Octane0411/open-vibe-island) | AI-agent bridge, hook system | GPL v3 |
| [CodexIsland](https://github.com/ericjypark/codex-island) | Token usage & cost visualisations | MIT |

Because it combines GPL v3 sources, **AllNotch is distributed under the [GNU General Public License v3](LICENSE)**. Original copyright notices are retained in source headers as required.

---

<p align="center">Made with ❤️ — <a href="https://github.com/thib-crypt/AllNotch">AllNotch</a></p>
