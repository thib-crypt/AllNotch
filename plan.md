# AllNotch — Guide de développement complet

> **AllNotch** est une app macOS native qui fusionne trois projets open-source pour transformer le notch du MacBook en une surface de contrôle tout-en-un : médias, stats système, agents IA, et suivi de consommation de tokens.

***

## 1. Vue d'ensemble du projet

### Les trois sources

| Projet | Repo | Licence | Rôle dans AllNotch |
|--------|------|---------|-------------------|
| **Atoll** | [Ebullioscopic/Atoll](https://github.com/Ebullioscopic/Atoll) | GPL v3 | Base UI/UX notch, médias, stats système, animations SwiftUI |
| **Open Island** | [Octane0411/open-vibe-island](https://github.com/Octane0411/open-vibe-island) | GPL v3 | Bridge agents IA, hook system, jump-back terminal |
| **CodexIsland** | [ericjypark/codex-island](https://github.com/ericjypark/codex-island) | MIT | UI pill notch-native, visualisations usage/coût tokens, suivi 5h/7j |

> ⚠️ **Licence** : Atoll et Open Island sont sous GPL v3, CodexIsland sous MIT. La fusion impose que AllNotch soit distribué sous **GPL v3**.

### Ce que AllNotch apporte de neuf

- **Un seul notch** pour tout : médias, système, agents IA, coût tokens — sans jongler entre plusieurs apps
- **Onglet Agents** intégré dans le shell UI d'Atoll, alimenté par le bridge d'Open Island
- **Onglet Usage/Cost** intégré dans le même panel, repris et amélioré de CodexIsland
- **Cohérence visuelle** : une seule charte d'animation, un seul système de settings

***

## 2. Prérequis de développement

| Outil    | Version minimale | Notes                                     |
| ----------| ------------------| -------------------------------------------|
| macOS    | 14.0+            | optimisé pour macOS 15+                   |
| Xcode    | 15+              | nécessaire pour le target app             |
| Swift    | 6.2              | requis par Open Island                    |
| Node.js  | 18+              | uniquement pour `create-dmg` (packaging)  |
| Homebrew | récent           | pour `create-dmg` et la distribution cask |

MacBook avec notch recommandé pour le développement (MBP 14/16 pouces Apple Silicon).

***

## 3. Architecture cible

### Vue d'ensemble

```
AllNotch/
├── AllNotch.xcodeproj              ← Xcode project principal
├── Package.swift                   ← Dépendances SPM (Sparkle, etc.)
│
├── Sources/
│   ├── AllNotchApp/                ← Shell SwiftUI + AppKit (base Atoll)
│   │   ├── App.swift
│   │   ├── NotchOverlay/           ← Fenêtre notch, expand/collapse
│   │   ├── Tabs/                   ← Media | Stats | Agents | Usage | Timers | Clipboard
│   │   ├── LockScreen/             ← Widgets lock screen (Atoll)
│   │   └── Settings/               ← Fenêtre settings unifiée
│   │
│   ├── AllNotchCore/               ← Modèles & état global partagés
│   │   ├── NotchState.swift        ← État expand/collapse/hover
│   │   ├── TabModel.swift          ← Enum des onglets disponibles
│   │   └── Preferences.swift      ← UserDefaults centralisés
│   │
│   ├── AgentBridge/                ← Open Island Core adapté
│   │   ├── BridgeServer.swift      ← Serveur Unix socket IPC
│   │   ├── SessionStore.swift      ← Sessions agents live
│   │   ├── HookPayload.swift       ← Modèles d'events hooks
│   │   └── TerminalJumper.swift    ← Jump-back terminal/IDE
│   │
│   ├── AgentHooks/                 ← CLI binary (Open Island Hooks adapté)
│   │   └── main.swift              ← Reçoit events agents → Unix socket
│   │
│   ├── AgentSetup/                 ← CLI installeur hooks
│   │   └── main.swift              ← Install/uninstall hooks dans ~/.claude, ~/.codex, etc.
│   │
│   ├── UsageBridge/                ← CodexIsland adapté
│   │   ├── UsageFetcher.swift      ← Appels endpoints Claude & Codex
│   │   ├── CostAggregator.swift    ← Lecture logs locaux JSONL
│   │   ├── UsageStore.swift        ← Store observable, polling configurable
│   │   └── Models/                 ← UsageWindow, CostEntry, TokenCount
│   │
│   └── MediaBridge/                ← Atoll media adapter
│       ├── NowPlayingProvider.swift
│       └── mediaremote-adapter/    ← Wrapper C/C++ (Atoll)
│
├── Frameworks/                     ← LottieAnimations (Atoll)
├── LottieAnimations/               ← Animations JSON (Atoll)
├── Resources/                      ← Assets, icônes, sons
└── scripts/
    ├── build.sh                    ← Build universel arm64+x86_64
    ├── package-app.sh              ← Packaging .app (Open Island)
    └── release.sh                  ← DMG + cask (CodexIsland)
```

### Flux de données

```
Agents (Claude Code / Codex / Cursor / Gemini…)
  ↓ hook event (SessionStart, PreToolUse, Stop…)
AgentHooks CLI (stdin → Unix socket)
  ↓ JSON envelope
BridgeServer (in-app, AgentBridge/)
  ↓ @Published SessionStore
NotchOverlay ← Onglet "Agents" mis à jour
  ↓ clic "Jump back"
TerminalJumper → Terminal / IDE ciblé

Claude/Codex API (endpoints usage non documentés)
  ↑ Bearer token (lu localement)
UsageFetcher (UsageBridge/)
  ↓ UsageWindow
NotchOverlay ← Onglet "Usage" mis à jour
  ↓ lecture logs locaux
CostAggregator → écran Cost (USD / tokens / tendance)
```

***

## 4. Description des onglets (UI/UX)

Le notch AllNotch fonctionne en **trois états** :

1. **Idle** — pill noire alignée au notch physique, coins squircle continus (CodexIsland)
2. **Peek** (hover) — pill s'élargit légèrement, affiche indicateurs clés : media en cours + agent actif + % usage 5h (CodexIsland hover pattern)
3. **Expanded** (clic) — panel complet avec onglets

### Tab Bar — les 6 onglets

```
[ 🎵 Media ]  [ 📊 Stats ]  [ 🤖 Agents ]  [ 💰 Usage ]  [ ⏱ Timers ]  [ 📋 Clipboard ]
```

#### Onglet Media (Atoll)
- Contrôles Apple Music / Spotify / any media
- Pochette album avec parallax hover
- Gestes horizontaux pour piste suivante/précédente ou ±10s
- Visualiseur audio temps réel (adapté de `rtaudio`)

#### Onglet Stats (Atoll)
- CPU, GPU, mémoire, réseau, disque
- Métriques via SMC (adapté de Stats project)
- Lecture température, fréquence par cœur

#### Onglet Agents (Open Island)
- Liste des sessions actives (agent + terminal + statut)
- Indicateur de phase : thinking / tool use / waiting / stopped
- Approbation de permissions inline
- Bouton "Jump back" → ramène au bon terminal/IDE
- Agents supportés : Claude Code, Codex, Cursor, Gemini CLI, OpenCode, Kimi CLI, Qoder, Qwen Code, Factory, CodeBuddy

#### Onglet Usage (CodexIsland)
- **Écran Usage** : Claude 5h + 7j / Codex 5h + 7j
  - 5 styles de chart : Ring, Bar, Stepped, Numeric, Sparkline
  - Cmd+clic pour cycler les styles
  - Reset timing affiché
- **Écran Cost** (swipe horizontal) : estimation dépenses du jour et du mois
  - 4 modes : USD, VALUE (vs abonnement), TOKENS, TREND
  - Lecture logs locaux `~/.claude/projects/**/*.jsonl` et `~/.codex/sessions/`
  - Aucune donnée envoyée hors device
- Glow "Cobalt" autour du pill pendant un refresh
- Low Power Mode : glow masqué sauf pendant le travail actif

#### Onglet Timers (Atoll)
- Timers multiples avec design iOS-like
- Widgets lock screen pour timers

#### Onglet Clipboard (Atoll)
- Historique du presse-papier
- Recherche rapide

### Animations & interactions

Reprises de CodexIsland pour la couche notch-native :
- Coin continus (squircle) qui correspondent aux coins hardware du notch
- Pill black qui s'élargit en douceur (spring animation)
- Click-through en dehors de la silhouette visible → la menubar reste accessible
- Fallback sur non-notch Macs : pill 200×28 px centrée en haut

Reprises d'Atoll pour les interactions dans le panel :
- Parallax hover sur les pochettes media
- Animations Lottie pour les états de chargement
- Transitions fluides entre onglets
- Gestes deux doigts (swipe down pour ouvrir, swipe up pour fermer)

***

## 5. Plan de fusion — étapes détaillées

### Phase 0 — Setup (1-2 jours)

```bash
# 1. Créer le repo AllNotch
gh repo create AllNotch --public --license gpl-3.0

# 2. Cloner les trois sources pour référence
git clone https://github.com/Ebullioscopic/Atoll.git _ref/Atoll
git clone https://github.com/Octane0411/open-vibe-island.git _ref/OpenIsland
git clone https://github.com/ericjypark/codex-island.git _ref/CodexIsland
```

Créer un projet Xcode vierge `AllNotch.xcodeproj` avec les targets :
- `AllNotchApp` (macOS App, SwiftUI lifecycle)
- `AllNotchCore` (Framework)
- `AgentBridge` (Framework)
- `AgentHooks` (Command Line Tool)
- `AgentSetup` (Command Line Tool)
- `UsageBridge` (Framework)

### Phase 1 — Base UI Notch (1 semaine)

Reprendre depuis Atoll :
- `DynamicIsland/NotchWindowController.swift` → Fenêtre NSWindow level `.statusBar`, `collectionBehavior: .canJoinAllSpaces`
- Le système de hover detection sur la zone notch
- L'animation expand/collapse avec spring physics
- La gestion du fallback non-notch

Reprendre depuis CodexIsland :
- `Sources/Window/` → gestion de la pill noire, squircle corners, click-through
- `Sources/Views/NotchShapeView.swift` → forme pill qui suit le hardware notch
- L'animation "peek" au hover (élargissement partiel)

**Point d'attention** : CodexIsland n'utilise pas de fichier `.xcodeproj` — il compile avec `swiftc` directement via `build.sh`. Adapter son code Window en target Xcode propre.

### Phase 2 — Onglets Media & Stats (3-4 jours)

Copie directe depuis Atoll :
- `DynamicIsland/Tabs/MediaTab/` → player, artwork, gestes
- `DynamicIsland/Tabs/StatsTab/` → CPU/GPU/RAM/réseau
- `Frameworks/mediaremote-adapter/` → wrapper C/C++ pour media info
- `LottieAnimations/` → animations JSON

Ajouter `MediaBridge/NowPlayingProvider.swift` comme wrapper observable (`@Observable` Swift 5.9+).

### Phase 3 — Onglet Agents (4-5 jours)

> **État (tranche 1 — Claude Code, livrée)** : OpenIslandCore intégré comme package SPM local (`Packages/AgentBridge`, module interne `OpenIslandCore` préservé) ; produits `AgentHooks`/`AgentSetup`. Chemins runtime débrandés (`~/Library/Application Support/AllNotch`, socket `/tmp/allnotch-<uid>.sock`, binaire `AllNotchHooks`). Onglet **Agents** câblé (`NotchViews.agents` + `TabModel`, flag `enableAgentsFeature`) via `AgentBridgeController` (BridgeServer + LocalBridgeClient observer → `SessionState` observable). Jump-back porté (`TerminalJumpService`). Binaire `AgentHooks` embarqué dans `AllNotch.app/Contents/Helpers/`. Install des hooks Claude depuis l'onglet. Build app + package verts. **Reste** : autres agents (Codex/Cursor/Gemini/…), enrichissement UI (markdown, phases détaillées), discovery/monitoring de process, section Settings dédiée.

Reprendre depuis Open Island :

```
Sources/OpenIslandCore/ → Sources/AgentBridge/
  BridgeServer.swift          (Unix socket IPC, écoute sur ~/Library/Application Support/AllNotch/bridge.sock)
  SessionStore.swift          (sessions @Observable)
  HookPayload.swift           (décodage JSON hooks)
  AgentDetector.swift         (découverte sessions via ps/lsof)
  TerminalJumper.swift        (jump-back)
```

```
Sources/OpenIslandHooks/ → Sources/AgentHooks/
  main.swift                  (CLI léger, stdin → socket)
```

```
Sources/OpenIslandSetup/ → Sources/AgentSetup/
  main.swift                  (install/uninstall hooks dans ~/.claude, ~/.codex, etc.)
```

Créer `Sources/AllNotchApp/Tabs/AgentsTab.swift` qui observe `AgentBridge.SessionStore`.

**Changements requis** : remplacer les chemins `~/Library/Application Support/OpenIsland/` par `~/Library/Application Support/AllNotch/` dans tous les fichiers.

### Phase 4 — Onglet Usage (3-4 jours)

Reprendre depuis CodexIsland :

```
Sources/Usage/UsageFetcher.swift  → UsageBridge/UsageFetcher.swift
Sources/Usage/UsageStore.swift    → UsageBridge/UsageStore.swift
Sources/Cost/                     → UsageBridge/Cost/
Sources/Model/                    → UsageBridge/Models/
Sources/Views/UsageView.swift     → AllNotchApp/Tabs/UsageTab/UsageView.swift
Sources/Views/CostView.swift      → AllNotchApp/Tabs/UsageTab/CostView.swift
Sources/Theme/                    → intégrer dans la charte Atoll
```

Adapter les `UserDefaults` keys de `MacIsland.*` vers `AllNotch.*`.

### Phase 5 — Settings unifiés (2-3 jours)

Créer `Sources/AllNotchApp/Settings/SettingsWindow.swift` avec les sections :

- **General** : launch at login, onglets visibles, comportement hover
- **Notch** : style animations, Low Power Mode, sons
- **Media** : source, gestes, visualiseur
- **Stats** : métriques activées, fréquence de polling
- **Agents** : install/uninstall hooks (appel AgentSetup), sons de notifications
- **Usage** : providers visibles, intervalle refresh (5/15/30 min), style chart par défaut, mode token counting
- **About** : version, liens GitHub, licence

### Phase 6 — Polish & distribution (1 semaine)

- Signer l'app avec Apple Developer ID (ou documenter la procédure `xattr -dr` comme CodexIsland)
- Configurer Sparkle pour auto-update (reprendre la config d'Open Island : `appcast.xml` + clé EdDSA)
- Adapter `scripts/build.sh` pour compilation universelle arm64 + x86_64
- Adapter `scripts/release.sh` pour DMG + notarisation
- Publier un Homebrew Cask

***

## 6. Dépendances (Package.swift)

```swift
// Package.swift
let package = Package(
    name: "AllNotch",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Auto-update (Open Island / CodexIsland)
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
        // Animations (Atoll)
        .package(url: "https://github.com/airbnb/lottie-spm", from: "4.0.0"),
        // Launch at login (CodexIsland reference)
        .package(url: "https://github.com/sindresorhus/LaunchAtLogin-Modern", from: "1.0.0"),
    ],
    targets: [
        .target(name: "AllNotchCore", dependencies: []),
        .target(name: "AgentBridge", dependencies: ["AllNotchCore"]),
        .target(name: "UsageBridge", dependencies: ["AllNotchCore"]),
        .executableTarget(name: "AgentHooks", dependencies: ["AgentBridge"]),
        .executableTarget(name: "AgentSetup", dependencies: ["AgentBridge"]),
    ]
)
// Note : AllNotchApp est un target Xcode, pas SPM (AppKit/SwiftUI lifecycle)
```

***

## 7. Permissions requises (entitlements)

```xml
<!-- AllNotch.entitlements -->
<key>com.apple.security.app-sandbox</key><false/>  <!-- requis pour Unix socket IPC -->
<key>com.apple.security.automation.apple-events</key><true/>  <!-- jump-back terminal -->
<key>com.apple.security.network.client</key><true/>  <!-- usage API endpoints -->
```

Permissions demandées au premier lancement (avec explication contextuelle) :
- **Accessibility** — détection sessions agents, jump-back terminal
- **Screen Recording** — détection fenêtres actives (Atoll)
- **Calendar** — widgets lock screen (Atoll, optionnel)
- **Music** — contrôles médias Apple Music (Atoll)
- **Camera** — indicateur Live Activity caméra active (Atoll, optionnel)

***

## 8. Compatibilité agents & terminaux

### Agents supportés (Open Island)

| Agent | Fichier config hooks | Event clé |
|-------|---------------------|-----------|
| Claude Code | `~/.claude/settings.json` | SessionStart, PreToolUse, Stop |
| Codex CLI | `~/.codex/config.toml` | SessionStart, UserPromptSubmit, Stop |
| Cursor | `~/.cursor/hooks.json` | beforeSubmitPrompt, afterFileEdit, stop |
| Gemini CLI | `~/.gemini/settings.json` | SessionStart, PreToolUse, Stop |
| OpenCode | `~/.config/opencode/plugins/` | Plugin JS auto-installé |
| Kimi CLI | `~/.kimi/config.toml` | Même payload que Claude |
| Qoder / Qwen / Factory / CodeBuddy | `~/.{agent}/settings.json` | Fork Claude, même format |

### Usage/Cost supporté (CodexIsland)

| Provider | Auth source | Endpoint |
|----------|------------|---------|
| Claude | `CLAUDE_CODE_OAUTH_TOKEN` → Keychain → OAuth refresh | `api.anthropic.com/api/oauth/usage` |
| Codex | `~/.codex/auth.json` | `chatgpt.com/...` (non documenté) |

***

## 9. Points d'attention critiques

### 1. Compatibilité build systems
Atoll utilise un `.xcodeproj` classique, Open Island un `Package.swift`, et CodexIsland un simple `swiftc` direct. La cible est un `.xcodeproj` unique qui importe les modules SPM via "Swift Packages" dans Xcode.

### 2. Sandbox vs entitlements
Le hook system d'Open Island nécessite `com.apple.security.app-sandbox = false` pour les sockets Unix. Documenter ce choix explicitement dans le README.

### 3. Endpoints non documentés
Les endpoints Claude et Codex pour le suivi d'usage (CodexIsland) peuvent changer sans préavis. Prévoir un fallback gracieux : si le fetch échoue, afficher les données locales (logs JSONL) uniquement.

### 4. Nested radius dans le notch
Les éléments internes du panel doivent respecter la règle `inner-radius = outer-radius - gap` pour que les coins s'alignent avec le hardware notch.

### 5. Gestion multi-moniteurs
CodexIsland et Atoll gèrent tous les deux un seul island sur un seul écran. AllNotch doit choisir l'écran avec le notch hardware en priorité, puis `NSScreen.main`.

### 6. Swift version
Open Island requiert Swift 6.2 (concurrence stricte). S'assurer que tous les modules compilent en mode Swift 6 avec `Sendable` et acteurs correctement annotés.

***

## 10. État de l'art : comparatif des trois sources

| Capacité | Atoll | Open Island | CodexIsland | AllNotch |
|----------|-------|-------------|-------------|----------|
| UI notch (pill + expand) | ✅ SwiftUI riche | ✅ basique | ✅ pill native précise | ✅ meilleur des trois |
| Médias | ✅ complet | ❌ | ❌ | ✅ |
| Stats système | ✅ complet | ❌ | ❌ | ✅ |
| Agents IA (live sessions) | ❌ | ✅ 10 agents | ❌ | ✅ |
| Hook system | ❌ | ✅ | ❌ | ✅ |
| Jump-back terminal | ❌ | ✅ 15+ terminaux | ❌ | ✅ |
| Usage tokens (5h/7j) | ❌ | partiel | ✅ Claude + Codex | ✅ |
| Coût estimé ($) | ❌ | ❌ | ✅ | ✅ |
| Charts usage | ❌ | ❌ | ✅ 5 styles | ✅ |
| Lock screen widgets | ✅ | ❌ | ❌ | ✅ |
| Timers, presse-papier | ✅ | ❌ | ❌ | ✅ |
| Auto-update Sparkle | ✅ | ✅ | ✅ | ✅ |
| Homebrew Cask | ✅ | ✅ | ✅ | ✅ |
| Licence | GPL v3 | GPL v3 | MIT | **GPL v3** |

***

## 11. Commandes de démarrage rapide

```bash
# Cloner AllNotch (une fois créé)
git clone https://github.com/votre-org/AllNotch.git
cd AllNotch
open AllNotch.xcodeproj

# Build universel (dev)
swift build -c release --product AgentHooks
swift build -c release --product AgentSetup

# Installer les hooks agents (après premier lancement app)
.build/release/AgentSetup install          # Claude Code + Codex
.build/release/AgentSetup installGemini    # Gemini CLI
.build/release/AgentSetup installKimi      # Kimi CLI

# Build app complète
zsh scripts/build.sh

# Packaging DMG
zsh scripts/release.sh
```

***

*Tous les repos sources sont disponibles sur GitHub : [Atoll](https://github.com/Ebullioscopic/Atoll) (GPL v3), [Open Island](https://github.com/Octane0411/open-vibe-island) (GPL v3), [CodexIsland](https://github.com/ericjypark/codex-island) (MIT).*