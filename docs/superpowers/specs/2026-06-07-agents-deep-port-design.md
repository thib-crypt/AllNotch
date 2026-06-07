# Agents — portage profond OpenIsland dans AllNotch

> Date : 2026-06-07
> Branche : `feature/openvibe-interactive-multiagent`

## Objectif

Rendre l'onglet Agents d'AllNotch « 100 % fonctionnel » en reprenant les
mécaniques profondes d'Open Vibe Island (`_ref/OpenIsland`) : cycle de vie
fiable des sessions, suppression manuelle, permissions/questions inline, grille
d'agents (« space invaders ») dans le notch fermé en cas d'attention, et notch
qui s'étend en hauteur max sur la vue Agents.

L'app utilise déjà le package SPM local `OpenIslandCore` (BridgeServer +
LocalBridgeClient observer → `SessionState`), l'`AgentBridgeController`, et un
portage de `IslandSessionRow`. Le travail ci-dessous comble les écarts.

## Constat (écarts vs OpenIsland)

1. **Lifecycle cassé** : `AgentBridgeController.sessions` expose
   `state.sessions` — TOUTES les sessions, non filtrées. OpenIsland filtre par
   `AgentSession.isVisibleInIsland` et appelle `SessionState.removeInvisibleSessions()`.
   Conséquence : une session quittée (`SessionEnd`) reste affichée pour toujours.
2. **Pas de dismiss manuel** : `AgentsTabView` passe `onDismiss: nil`.
3. **Permissions/questions** : UI (`IslandSessionRow` → `onApprove`/`onAnswer`)
   et bridge (`BridgeServer.resolvePermission` / `answerQuestion`) présents, mais
   non validés de bout en bout.
4. **Grille « space invaders »** (`V6NotchContent.swift` / `AgentsGridBody`) :
   pas portée.
5. **Hauteur du notch** : la vue Agents subit la hauteur de base + blur au
   scroll, peu pratique pour répondre aux agents.

## Décisions de cadrage (validées)

- **Grille dans le notch fermé** : affichée **uniquement** quand au moins une
  session requiert l'attention (`liveAttentionCount > 0`). Sinon le notch fermé
  est inchangé.
- **Cycle de vie** : auto-suppression à la fin (hook `SessionEnd` + poll PID
  léger) **et** dismiss manuel.
- **Permissions** : inline fiable par requête. Pas d'allow-list persistante.
- **Monitoring** : hook `SessionEnd` + poll PID léger (réutilise
  `SessionState.refreshProcessLiveness` déjà dans le package), plutôt que de
  porter `ProcessMonitoringCoordinator`/`ActiveAgentProcessDiscovery` (lourds,
  vivent dans le target App d'OpenIsland).
- **Hauteur Agents** : nouveau cas `.agents` dans `dynamicNotchSize`, calqué sur
  `.terminal` (fraction de l'écran), sans toucher `.home`.

## Unités de travail

### U1 — Lifecycle & filtrage (`AgentBridgeController`)

- Remplacer `sortedSessions(state.sessions)` par un filtrage sur
  `isVisibleInIsland` avant tri : seules les sessions visibles s'affichent.
- Après chaque `apply(event)` : appeler `state.removeInvisibleSessions()` puis
  re-snapshot (`bridgeServer.updateStateSnapshot`).
- **Poll PID** : timer `@MainActor` (~3 s, démarré dans `startIfNeeded`, arrêté
  dans `stop`) qui :
  1. collecte les PID des sessions courantes (via `AgentSession` — champ pid),
  2. teste la liveness avec `kill(pid, 0) == 0` (ESRCH ⇒ mort),
  3. appelle `state.refreshProcessLiveness(aliveSessionIDs:)` (déjà présent),
  4. `removeInvisibleSessions()` + re-publication si changement.
  - Si une session n'expose pas de PID exploitable, elle reste gérée par les
    hooks seuls (fallback : dismiss manuel).
- `reconcileAttention()` continue de tourner sur la liste filtrée.

### U2 — Dismiss manuel

- `AgentBridgeController.dismiss(_ session:)` : `state.dismissSession(id:)` →
  `removeInvisibleSessions()` → re-publish + snapshot. (Optionnel : informer le
  bridge si une commande de dismiss côté serveur existe ; sinon purge locale.)
- `AgentsTabView` : passer `onDismiss: { bridge.dismiss(session) }`.

### U3 — Permissions / questions inline (validation)

- Vérifier de bout en bout via `IslandSessionRow` :
  - Approve / Deny / Allow-with-edits (`ApprovalAction` →
    `AgentBridgeController.resolve`).
  - Réponse à question structurée (`QuestionPromptResponse` → `answer`).
- À la résolution, la phase `waitingForApproval` / `waitingForAnswer` doit
  retomber (géré par `BridgeServer` qui relaie l'event suivant). Confirmer que
  la session sort de l'état « attention » et que la grille fermée se masque.
- Corriger tout point bloquant (sérialisation commande, correlation key, etc.).

### U4 — Grille « space invaders » (notch fermé, sur attention)

- Porter depuis `_ref/OpenIsland/Sources/OpenIslandApp/Views/V6NotchContent.swift` :
  `AgentGridCellState`, `AgentGridCell`, l'algo `balancedRows` / `cellGeometry`,
  et le rendu `AgentsGridBody` (running = couleur pleine, idle = ~22 %, waiting =
  pulse d'opacité). Adapter au design system AllNotch (`AgentDesignSystem`,
  `V6Palette` → couleurs AllNotch).
- Construire les cellules depuis `AgentBridgeController` : map des sessions
  visibles → `AgentGridCell.session(color:state:)`, avec cellule `.overflow(n)`
  au-delà de la capacité.
- **Affichage conditionnel** : injecter la grille dans le slot droit du notch
  fermé **seulement** si `liveAttentionCount > 0`. Intégration dans le rendu du
  notch fermé d'AllNotch (cf. `ContentView` / `DynamicIslandHeader`), en
  cohabitation non destructive avec le média/idle existant.
- **Tap** sur la grille → `NotificationCenter.post(.allNotchOpenAgents)` (ouvre
  l'onglet Agents, déjà câblé dans `ContentView`).
- Conserver le sneak-peek + son existants (`presentAttention`).

### U5 — Hauteur max sur la vue Agents

- Dans `ContentView.dynamicNotchSize`, ajouter un cas
  `coordinator.currentView == .agents` retournant une hauteur dynamique calquée
  sur `.terminal` : `min(screenHeight * fraction, …)`, fraction raisonnable
  (réutiliser `terminalMaxHeightFraction` ou une constante dédiée, ex. 0.6–0.7).
- Animation fluide : le changement de `currentView` est déjà animé par le
  système de transition existant ; vérifier que la transition de taille reste
  spring/douce. Ne **pas** modifier la hauteur du `.home`.
- Le blur au scroll : la hauteur étendue réduit le besoin de scroller ; si le
  blur de bord reste gênant en vue Agents, l'atténuer/désactiver spécifiquement
  pour `.agents` (sans toucher les autres onglets).

## Risques / points d'attention

- **PID indisponible** : si `AgentSession` n'expose pas de PID fiable pour les
  sessions hook-managed, le poll PID ne couvre que les sessions qui en ont ; le
  reste repose sur `SessionEnd` + dismiss manuel (acceptable).
- **Cohabitation notch fermé** : la grille ne doit pas casser le layout
  média/idle ni la largeur du pill ; n'apparaît que sur attention.
- **Concurrency Swift 6** : respecter `@MainActor` sur le controller ; le poll
  PID lit des PID puis hop sur le main actor pour muter l'état.
- **Régression home** : la hauteur `.home` doit rester strictement inchangée.

## Critères de réussite

1. Lancer puis quitter une session Claude Code → elle disparaît du notch
   (auto, via `SessionEnd`), sans intervention.
2. Tuer brutalement le terminal → la session disparaît (poll PID) ou peut être
   supprimée manuellement.
3. Bouton/geste de suppression fonctionne sur n'importe quelle session.
4. Une demande de permission live s'approuve/refuse depuis le notch et l'état
   d'attention retombe.
5. Une question d'agent se répond depuis le notch.
6. Quand un agent demande l'attention, la grille apparaît dans le notch fermé ;
   tap → onglet Agents ; elle disparaît quand l'attention est résolue.
7. En vue Agents, le notch s'étend en hauteur max avec une animation fluide ;
   l'onglet Home conserve sa hauteur d'origine.
