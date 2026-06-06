# AllNotch

**AllNotch** is a native macOS app that turns the MacBook notch into an all-in-one control surface: media, system stats, AI agents, and token-usage / cost tracking — all in a single notch, without juggling several apps.

## Status

Early development. The current foundation is the full notch UI/UX shell (media, system stats, lock-screen widgets, timers, clipboard, settings) inherited from Atoll. The **Agents** tab (live agent sessions + hooks, from Open Island) and the **Usage / Cost** tab (token usage and spend, from CodexIsland) are being grafted on next.

## Credits & license

AllNotch is a **fork of [Atoll](https://github.com/Ebullioscopic/Atoll)** (GPL v3) and additionally integrates ideas and code from:

- **[Atoll](https://github.com/Ebullioscopic/Atoll)** — notch UI/UX, media, system stats, animations *(GPL v3)*
- **[Open Island](https://github.com/Octane0411/open-vibe-island)** — AI-agent bridge, hook system, jump-back terminal *(GPL v3)*
- **[CodexIsland](https://github.com/ericjypark/codex-island)** — notch-native usage/cost visualizations *(MIT)*

Because it combines GPL v3 sources, **AllNotch is distributed under the GNU General Public License v3** — see [LICENSE](LICENSE). Original copyright notices are retained in the source headers as required by the license.

## Requirements

- macOS 14+ (optimized for macOS 15+), a MacBook with a notch recommended
- Xcode 15+

## Build

```bash
open AllNotch.xcodeproj
# then build & run the "AllNotch" scheme
```

The project resolves its Swift Package dependencies automatically on first build.
