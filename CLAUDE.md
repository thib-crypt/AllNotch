# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

AllNotch is a native macOS notch app (menu-bar/`LSUIElement` agent, no Dock icon) that turns the MacBook notch into a control surface for media, system stats, AI agents, and usage/cost tracking. It is a **GPL v3 fork of [Atoll](https://github.com/Ebullioscopic/Atoll)**, with **[Open Island](https://github.com/Octane0411/open-vibe-island)** (Agents) and **[CodexIsland](https://github.com/ericjypark/codex-island)** (Usage/Cost) being grafted on. The roadmap lives in `plan.md`.

### Naming, structure, and the de-branding boundary

- The Xcode project is `AllNotch.xcodeproj` and the user-facing scheme is **`AllNotch`**, but the **build target is named `DynamicIsland`** and the source folder is `DynamicIsland/`. The `@main` struct is `DynamicNotchApp`. These internal names are kept deliberately to avoid massive pbxproj churn — they are invisible to users. Don't rename them.
- De-branding rule: rename only the **visible standalone word "Atoll"** (About page, menus, UI strings, permission prompts) to "AllNotch". **Preserve**: GPL copyright headers (`* Atoll (DynamicIsland)`), the external SDK name `AtollExtensionKit` and its `Atoll*` API types, and internal identifiers (XPC service `com.ebullioscopic.Atoll.xpc`, `AtollDistributedNotifications` strings, menu item ids like `Atoll.Focus.Menu`, audio key `Atoll_Virtual_Tap`, `os.Logger` subsystems). Fork attribution lives in `ReadMe.md` only, never in the app.

## Build, run, verify

```bash
# Build (CLI). First build resolves ~18 SPM packages (slow, minutes) — run in background.
xcodebuild -project AllNotch.xcodeproj -scheme AllNotch -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -clonedSourcePackagesDirPath /tmp/allnotch-spm build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

# DO NOT run or launch the app. The user will run the app manually in Xcode.
```

- **`xcodebuild` is the source of truth.** SourceKit "Cannot find type" / "No such module OpenIslandCore/Defaults" diagnostics in the editor are stale-index noise here, not real errors.
- There is no separate test suite or linter wired up; verification = a green `xcodebuild` build. Do not attempt to run the application yourself.
- **Claude cannot screenshot the running app** (the shell lacks Screen Recording TCC permission; the `LSUIElement` agent app is filtered out of computer-use screenshots). To visually confirm UI, **ask the user to look at their notch**.

## Architecture

### Notch UI core (from Atoll)

- **`DynamicIslandViewCoordinator`** (`DynamicIsland/DynamicIslandViewCoordinator.swift`, `@MainActor ObservableObject`) is the central hub. It owns `currentView: NotchViews` (the active tab — `tabOrder` = home/shelf/timer/stats/colorPicker/notes/clipboard/terminal/agents/extensionExperience), `sneakPeek`, and `expandingView`. `SneakContentType` (defined here) enumerates everything the closed notch can briefly surface (volume, music, battery, `agentAttention`, extension live activities, …).
- **`managers/`** — one focused manager per system feature (media, battery, stats, clipboard, lock-screen widgets, timers, screen recording, HUD windows, …). Most are singletons (`.shared`) wiring AppKit/IOKit/CoreAudio to `@Published` state. This is the bulk of the codebase.
- **`components/`** — SwiftUI views grouped by feature (Notch, Music, Stats, Shelf, Settings, Agents, ScreenAssistant, LockScreen, …). Entry views are `ContentView.swift` and `DynamicIslandApp.swift`.
- App preferences use **`Defaults`** (sindresorhus); keys are declared in `DynamicIsland/models/Constants.swift` (`extension Defaults.Keys`). Feature toggles gate UI, e.g. `Defaults[.enableAgentsFeature]`.
- Xcode 16 **file-system synchronized groups**: any new `.swift` added under `DynamicIsland/` is auto-compiled — no pbxproj edit needed (but it also means an in-progress folder can break the whole target build).

### Agent bridge (from Open Island)

- Grafted as a **local SPM package** `Packages/AgentBridge` (referenced by the project). Internal module name `OpenIslandCore` is preserved; products are executables `AgentHooks` and `AgentSetup`. The package builds in **Swift 6.2 strict-concurrency**, isolated from the app target's `SWIFT_VERSION=5.0`.
- Wiring scripts: `scripts/integrate_agentbridge.rb` (idempotent) adds the package reference. **Warning:** the `xcodeproj` Ruby gem strips the synchronized-group `attributesByRelativePath` block on save; the script re-patches it — never hand-run the gem without restoring that attribute.
- In-app glue: `DynamicIsland/services/AgentBridgeController.swift` (`@MainActor ObservableObject`) starts a `BridgeServer` + observer client and streams `AgentEvent`s into observable session state. `AgentEnrollmentService.swift` normalizes hook install/uninstall/status across ~10 agents (Claude + forks reuse `ClaudeHookInstallationManager`; Codex/Cursor/Gemini/Kimi/OpenCode own managers). UI lives in `components/Agents/` and `components/Settings/AgentsSettings.swift`. Runtime paths are de-branded to `~/Library/Application Support/AllNotch`, socket `/tmp/allnotch-<uid>.sock`.
- **The hook helper must be statically self-contained.** Xcode always builds package products as dynamic frameworks (`@rpath/OpenIslandCore.framework`) even with `type: .static`, so an Xcode-built `AgentHooks` crashes (`dyld: Library not loaded`) once only its binary is copied to the app-support `bin/`. Fix in place: a **"Build & Embed Agent Helpers" run-script phase** runs `swift build -c release --product AgentHooks` (SwiftPM statically links the `OpenIslandCore` target in) and copies it to `Contents/Helpers/AgentHooks`. Verify with `otool -L .../AgentHooks | grep OpenIslandCore` → must be **empty**.
- Hooks are a Claude **Code** (CLI) feature; the Claude **Desktop** app does not fire `~/.claude/settings.json` hooks. Claude Code loads hooks only at **session start**, so enrolling an agent in Settings while its CLI is already running has no effect — the CLI must be quit and relaunched.
- `os.Logger` must be referenced fully-qualified (`import os`) — the app target defines its own `Logger` that shadows it. Diagnose the agent attention pipeline by streaming `/usr/bin/log stream --predicate 'subsystem == "com.allnotch.agents"' --level info` (use the absolute `/usr/bin/log` path; zsh shadows `log`).

## Gotchas

- **Shelf has two stores; only one renders.** `ShelfStateViewModel.shared` (items: `ShelfItem`, persisted via `ShelfPersistenceService`) is what the visible shelf and header show. `TrayDrop.shared` (`DropItem`) is legacy/dead — writing to it "works" silently but never appears in the UI. Any "add to shelf" feature must target `ShelfStateViewModel` (e.g. `MacshotManager.addFileURLToShelf`).
- `DynamicIsland/macshot/` is an in-progress, untracked screenshot feature pulled into the build via the synchronized group; historically it broke the whole target build. Confirm it still compiles before assuming an unrelated change is at fault.
- Reference clones of the three upstream sources live in `_ref/` (gitignored): `_ref/Atoll`, `_ref/OpenIsland`, `_ref/CodexIsland`. Design specs are in `docs/superpowers/specs/`.

## Not yet wired (future work)

Codex Desktop app-server (`CodexAppServer.swift`), the Usage/Cost dashboard (CodexIsland phase), and the Watch relay. `BridgeServer.handleGeminiHook` lacks permission/question cases, so Gemini approval prompts can't surface — only lifecycle events do.
