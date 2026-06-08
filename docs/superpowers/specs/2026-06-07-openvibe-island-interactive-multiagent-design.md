# OpenVibe Island — chantier 1 : expérience interactive multi-agents

**Date :** 2026-06-07
**Statut :** conception, en attente de revue
**Périmètre :** premier des plusieurs sous-systèmes ; voir « Hors périmètre » pour la suite.

## Contexte

AllNotch (fork GPL d'Atoll) a déjà grafté le pont d'agents d'OpenVibe Island
(`open-vibe-island`) sous forme de package SPM local `Packages/AgentBridge`
(module interne `OpenIslandCore`). À ce jour seul **« slice 1 = Claude Code »**
est câblé côté app : `AgentBridgeController` démarre le `BridgeServer` + un
observateur, l'onglet Agents liste les sessions et le jump-back fonctionne. Le
package contient déjà tout le cœur (10 agents, flux de permission, résolution,
sons d'OpenIsland), mais l'UI et le contrôleur n'en exposent qu'une fraction.

Ce chantier comble l'écart pour livrer **l'expérience interactive multi-agents
complète** : enrôler tous les agents, approuver/refuser/répondre depuis la
notch, et faire surgir la notch sur les événements « attention requise » avec
sons.

## Objectifs

1. **Enrôlement multi-agents** — installer/désinstaller/détecter les 10 agents
   depuis une page Réglages dédiée, avec intention tri-state persistée.
2. **Permissions interactives** — approuver, refuser ou répondre à une demande
   d'agent directement depuis la notch, débloquant le process du hook en attente.
3. **Mode notification + sons** — surgissement automatique de la notch (surface
   hybride) sur les événements requérant attention, avec sons configurables.

## Hors périmètre (chantiers suivants, specs séparées)

- **Codex Desktop app-server** (`CodexAppServer.swift`) — cycle thread/turn
  temps réel + deep-link `codex://`.
- **Tableau de bord Usage/coût** (`ClaudeUsage`/`CodexUsage`) — c'est la phase
  *CodexIsland* du roadmap, séparée.
- **Watch relay** (`WatchHTTPEndpoint`/`WatchNotificationRelay`) — companion iOS.
- **i18n complète** — on ajoute les nouvelles clés en anglais ; la traduction
  zh-Hans est différée.

## Architecture

Trois unités, chacune avec une responsabilité claire et une interface testable.

### Unité A — `AgentEnrollmentService` (@MainActor, ObservableObject)

**Rôle :** façade unique normalisant l'install/désinstall/statut des 10 agents
derrière `AgentIdentifier`, adossée à `AgentIntentStore` (intention tri-state,
jamais de réinstallation silencieuse d'un agent `uninstalled`).

**Interface :**
```
func status(for: AgentIdentifier) -> AgentEnrollmentStatus   // .notInstalled / .installed / .needsRepair / .agentMissing
func isAgentDetectedOnDisk(_:) -> Bool                        // config dir présent
func install(_: AgentIdentifier) throws
func uninstall(_: AgentIdentifier) throws
func refreshAll()                                            // recalcule @Published statuses
@Published var statuses: [AgentIdentifier: AgentEnrollmentStatus]
```

**Dépendances :** les `*HookInstallationManager` par agent + `ManagedHooksBinary`
(binaire `AgentHooks` embarqué dans `Contents/Helpers/`), `AgentIntentStore`.

**Adaptateur interne :** un `switch` sur `AgentIdentifier` route vers le bon
manager. Familles :
- **Forks Claude** (`claudeCode`, `qoder`, `qwenCode`, `factory`, `codebuddy`,
  `kimi`) → `ClaudeHookInstallationManager` / `KimiHookInstallationManager`
  pointé sur le `ClaudeConfigDirectory` propre à l'agent.
- **Hook simple** (`codex`, `cursor`, `gemini`) → leur manager respectif, même
  signature `install(hooksBinaryURL:)` / `uninstall()` / `status()`.
- **Plugin** (`openCode`) → `OpenCodePluginInstallationManager`
  (`isInstalled`/`pluginRegistered`, pas de binaire de hook).

Tous les agents partagent **le même binaire `AgentHooks`** embarqué ; il
dispatche par `--source <agent>` (déjà implémenté dans `OpenIslandHooksCLI`).

### Unité B — Permissions interactives (extension d'`AgentBridgeController`)

**Rôle :** envoyer les résolutions utilisateur au `BridgeServer` qui débloque le
process du hook en attente.

**Ajouts au contrôleur :**
```
private let commandClient = BridgeCommandClient()
func resolve(_ session: AgentSession, _ action: ApprovalAction)   // → .resolvePermission(sessionID, resolution)
func answer(_ session: AgentSession, _ response: QuestionPromptResponse) // → .answerQuestion(sessionID, response)
```
`ApprovalAction` (`deny`/`allowOnce`/`allowWithUpdates`) → `PermissionResolution`.
Les envois `BridgeCommandClient.send(...)` sont bloquants/socket → exécutés hors
du MainActor (Task détaché), résultat répercuté dans `statusMessage`.

**Flux :** hook PreToolUse/permissionRequest → `BridgeServer` garde la connexion
ouverte + émet `permissionRequested` → observateur peuple
`session.permissionRequest` → la carte affiche le prompt → clic → `resolve(...)`
→ `BridgeServer.resolvePendingClaudeInteraction(...)` répond au hook.

### Unité C — Surface notification (hybride) + sons

**Rôle :** faire surgir la notch et présenter une carte interactive quand une
session passe en `waitingForApproval`/`waitingForAnswer`.

**Surgissement :** `AgentBridgeController.apply(event)` détecte une transition
*vers* `requiresAttention` et appelle un nouveau
`AgentNotificationPresenter` qui :
1. déclenche `DynamicIslandViewCoordinator.toggleSneakPeek(status:type:)` avec un
   nouveau `SneakContentType.agentAttention(session)` — surgissement transitoire
   cohérent avec musique/batterie ;
2. optionnellement ouvre la notch (`NotchViews.agents`) si l'utilisateur l'a
   activé (`Defaults[.agentAutoOpenNotch]`).

**Carte réutilisable `AgentNotificationCard`** : rend `permissionRequest` (boutons
Allow/Deny + « allow with updates » si `suggestedUpdates`) ou `questionPrompt`
(options + champ libre si `allowsFreeform`). Utilisée à deux endroits :
- dans l'onglet Agents (remplace/enrichit `AgentSessionRow` quand attention) ;
- dans le contenu du sneak-peek agent.

**Sons :** un `AgentSoundPlayer` joue un son système configurable
(`Defaults[.agentSoundName]`, `Defaults[.agentSoundsEnabled]`) à l'arrivée d'un
événement attention. Réutilise `NSSound(named:)`.

### Réglages — onglet « Agents »

Nouveau `SettingsTab.agents` (groupe `.integrations`, icône `cpu`), vue
`AgentsSettingsView` :
- **Liste des 10 agents** : nom, couleur de marque, état détecté
  (`isAgentDetectedOnDisk`), toggle install/désinstall appelant
  `AgentEnrollmentService`, badge d'état (installé / non installé / à réparer /
  agent absent).
- **Section notifications** : toggles `agentSoundsEnabled`, sélecteur de son,
  `agentAutoOpenNotch`, `enableAgentsFeature`.

## Flux de données (récap)

```
Hook CLI (AgentHooks --source X)
        │  socket /tmp/allnotch-<uid>.sock
        ▼
   BridgeServer ──emit──▶ LocalBridgeClient(observer) ──▶ SessionState
        ▲                                                      │
        │ resolvePermission / answerQuestion                   ▼
   BridgeCommandClient ◀── AgentBridgeController ──▶ sessions[@Published]
                                  │                       │
                                  ▼                       ▼
                    AgentNotificationPresenter      AgentsTabView / AgentNotificationCard
                       (sneakPeek + son)                    Réglages: AgentsSettingsView
```

## Gestion des erreurs

- **Install/désinstall échoue** (perms fichier, config absente) → l'erreur
  remonte dans `AgentEnrollmentStatus.needsRepair` + message ; le toggle revient
  à son état réel après `refreshAll()`.
- **Agent non installé sur disque** (`~/.codex` absent, etc.) → état
  `agentMissing`, toggle désactivé avec explication.
- **`BridgeCommandClient.send` timeout/échec** → `statusMessage` signale l'échec,
  la carte reste affichée pour réessayer ; le hook côté agent retombera sur son
  propre timeout (45 s) sans bloquer indéfiniment.
- **Binaire `AgentHooks` absent du bundle** → install bloquée avec message
  explicite (déjà géré pour Claude).

## Stratégie de test

- **Package (`OpenIslandCore` / smoke)** : un test bout-en-bout par famille
  d'agent — serveur + observateur sur socket temporaire, lancer
  `AgentHooks --source <agent>` avec un payload permission, asserter
  `permissionRequested`, envoyer `resolvePermission`, asserter que le hook reçoit
  la résolution. Étend le `BridgeSmokeTest` existant.
- **`AgentEnrollmentService`** : tests d'install/désinstall sur des répertoires
  de config temporaires (HOME redirigé), vérifiant la persistance de l'intention
  et le respect de `uninstalled` au redémarrage.
- **UI** : vérification manuelle dans l'app (build + run ad-hoc, cf.
  `build-and-run-verification`) — install d'un agent, déclencher une vraie
  demande de permission, approuver depuis la notch, vérifier le déblocage.

## Risques / points d'attention

- Le binaire `AgentHooks` doit rester **auto-contenu** (statiquement lié,
  `otool -L` sans `OpenIslandCore.framework`) — déjà résolu par la phase
  run-script « Build & Embed Agent Helpers ». Tous les agents partagent ce même
  binaire, donc aucune régression attendue.
- `BridgeCommandClient` est synchrone/bloquant ; ne jamais l'appeler sur le
  MainActor.
- Respect de la frontière de de-branding : surfaces visibles dé-marquées, ids
  internes / SDK / GPL préservés.
</content>
