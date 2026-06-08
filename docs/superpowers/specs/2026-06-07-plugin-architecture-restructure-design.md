# AllNotch — Restructuration vers une architecture « plugin »

**Date** : 2026-06-07
**Statut** : Design validé (brainstorming) — en attente de relecture utilisateur avant plan d'implémentation
**Auteur** : Claude + Thibault

---

## 1. Contexte et problème

AllNotch (fork GPL d'Atoll, voir `CLAUDE.md`) accumule des fonctionnalités hétérogènes
greffées depuis plusieurs sources : Atoll (UI notch), Open Island (Agents), CodexIsland
(Usage), plus des features maison récentes (Todo, Screenshot/macshot). Chaque feature est
câblée « en dur » à **au moins 6 endroits** distincts du code :

1. l'enum `NotchViews` — `DynamicIsland/enums/generic.swift:73`
2. le tableau ordonné `tabOrder` — `DynamicIsland/DynamicIslandViewCoordinator.swift:110`
3. les conditions `if enable*Feature` dans `DynamicIsland/components/Tabs/TabSelectionView.swift`
4. l'enum `SettingsTab` + ses groupes — `DynamicIsland/components/Settings/SettingsView.swift`
5. une clé `enable*Feature` — `DynamicIsland/models/Constants.swift`
6. un ou plusieurs manager singleton + un dossier dans `components/`

**Conséquences** : ajouter ou retirer une feature est laborieux et propice aux oublis ;
la page Paramètres est devenue incohérente (24 `SettingsTab` répartis à la main dans 8
groupes) ; aucune frontière claire ne dit « voici tout ce qui constitue la feature X ».

**Objectif** : remplacer ces 6 points de couplage par **un seul**. Chaque feature devient
un *plugin* qui se décrit lui-même et s'enregistre dans un registre central. Ajouter une
feature = créer un fichier conforme à un protocole + l'ajouter à **une** liste.

---

## 2. Décisions cadrées (issues du brainstorming)

| Décision | Choix retenu | Raison |
|---|---|---|
| Niveau d'extensibilité | **Modules internes (compile-time)** | Pas de chargement de bundles tiers : évite la complexité macOS (signature, sandbox, stabilité ABI Swift, sécurité). On gagne la cohérence/découplage interne. |
| Surfaces couvertes par le contrat | **Les 4** : onglet notch, sneak peek, réglages, cycle de vie/service | Couvre tous les besoins actuels ; un plugin ne déclare *que* les surfaces qu'il utilise. |
| Stratégie de migration | **Pilote d'abord (incrémental)** | Build vert en continu ; les features non migrées continuent à fonctionner à l'ancienne. |
| Feature pilote | **Screenshot (macshot)** | Code neuf, isolé dans `macshot/`, non commité ; exerce réglages + cycle de vie + résultat sur notch/shelf, sans toucher de code stable. |
| Forme du contrat | **Noyau minimal + protocoles de capacité composables (option B)** | Plus propre et testable qu'un protocole unique à options ; ouvre chaque surface sans alourdir les autres. |
| Emplacement du code | **Interne au target `DynamicIsland`** (pas de SPM pour le pilote) | Zéro friction pbxproj / synchronized-group. Extraction en `Packages/PluginKit` possible plus tard. |
| Clés d'activation | **Réutiliser les `enable*Feature` existantes** | Pas de migration de préférences ; rétro-compatibilité immédiate. |

### Non-objectifs (YAGNI)

- Pas de chargement dynamique / marketplace de plugins tiers.
- Pas de package SPM dédié au démarrage.
- Pas de refactoring des features non concernées par la migration en cours.
- Pas de migration « big-bang » de toutes les features d'un coup.

---

## 3. Architecture

### 3.1 Arborescence cible

```
DynamicIsland/Plugins/
  Core/
    Plugin.swift              # protocole noyau
    PluginID.swift            # identité stable (String typé)
    PluginHost.swift          # registre + orchestrateur (@MainActor ObservableObject)
    Descriptors.swift         # TabDescriptor, SettingsGroup, SneakContribution
    Capabilities/
      NotchTabProviding.swift
      SettingsProviding.swift
      SneakPeekProviding.swift
      PluginLifecycle.swift
  Screenshot/
    ScreenshotPlugin.swift    # pilote : conforme à SettingsProviding + PluginLifecycle
  # (futures features migrées : Todo/, Timer/, Agents/, …)
```

Le dossier `Plugins/` est sous synchronized-group Xcode 16 → tout nouveau `.swift` est
compilé automatiquement (cf. `CLAUDE.md`). Les implémentations métier existantes
(`macshot/`, `managers/`, vues `components/`) **ne déménagent pas** ; le plugin est une
fine couche d'adaptation qui les référence.

### 3.2 Le protocole noyau

```swift
protocol Plugin: AnyObject {
    static var id: PluginID { get }                    // "screenshot", "todo", "agents"…
    var displayName: String { get }                    // localisé (String(localized:))
    var icon: String { get }                           // SF Symbol
    var defaultsEnableKey: Defaults.Key<Bool> { get }  // réutilise enable*Feature existant
}
```

`PluginID` est un `struct PluginID: RawRepresentable, Hashable` (String typé) pour éviter
les chaînes magiques disséminées.

### 3.3 Les protocoles de capacité (à la carte)

Un plugin se conforme **uniquement** aux capacités qu'il offre. Le host les découvre par
`as?`.

```swift
protocol NotchTabProviding: Plugin {
    var tab: TabDescriptor { get }            // label, icône, accentColor
    @MainActor func makeTabView() -> AnyView  // vue plein-panneau du notch ouvert
}

protocol SettingsProviding: Plugin {
    var settingsGroup: SettingsGroup { get }       // groupe sidebar (réutilise l'enum existant)
    @MainActor func makeSettingsView() -> AnyView  // section de réglages
}

protocol SneakPeekProviding: Plugin {
    // Le plugin émet des contributions notch-fermé via PluginHost.surface(_:from:).
    // Pas de méthode "pull" : c'est le plugin qui pousse quand un événement survient.
}

protocol PluginLifecycle: Plugin {
    @MainActor func activate()    // démarre le manager, l'item menu-bar, les raccourcis
    @MainActor func deactivate()  // arrête proprement
}
```

`TabDescriptor`, `SettingsGroup`, `SneakContribution` sont de petits descripteurs de
données (pas de logique) définis dans `Descriptors.swift`. `SettingsGroup` réutilise/mappe
l'enum de groupes déjà présent dans `SettingsView.swift` (core / mediaAndDisplay / system /
productivity / utilities / developer / integrations / info).

### 3.4 Le host

```swift
@MainActor
final class PluginHost: ObservableObject {
    static let shared = PluginHost()

    // LE SEUL endroit où l'on liste et ordonne les features.
    let allPlugins: [any Plugin] = [
        ScreenshotPlugin(),
        // … au fil de la migration : TodoPlugin(), TimerPlugin(), AgentsPlugin() …
    ]

    // Vues filtrées par capacité ET par état d'activation (defaultsEnableKey).
    var tabPlugins: [any NotchTabProviding] { … }
    var settingsPlugins: [any SettingsProviding] { … }
    var enabledPlugins: [any Plugin] { … }

    func bootstrap()                               // appelé au lancement
    func surface(_ contribution: SneakContribution, from id: PluginID)  // relai sneak peek
}
```

Responsabilités du host :
- **Registre ordonné** : `allPlugins` fixe l'ordre d'apparition (onglets, sidebar).
- **Activation** : au `bootstrap()`, lit chaque `defaultsEnableKey`, appelle `activate()`
  sur les plugins activés conformes à `PluginLifecycle`, puis pose un observateur Defaults
  par clé pour appeler `activate()`/`deactivate()` quand l'utilisateur bascule un toggle.
- **Relai sneak peek** : `surface(_:from:)` traduit une `SneakContribution` en
  `SneakContentType.plugin(id, payload)` et la transmet au coordinator existant.

Le host est **additif** : il alimente les points existants, il ne les remplace pas
brutalement (cf. §4).

---

## 4. Intégration dans l'existant (sans rien casser)

Règle d'or : **aucune suppression de code legacy tant que sa feature n'est pas migrée.**
Build vert à chaque étape ; les deux sources (legacy `if enable*` et plugins) coexistent
pendant la transition.

### 4.1 Onglets du notch

- `NotchViews` (`enums/generic.swift`) gagne **un seul** case générique :
  `case plugin(PluginID)`. Aucun case par feature.
- `TabSelectionView` continue d'émettre ses entrées codées en dur, **et** itère en plus sur
  `PluginHost.shared.tabPlugins`. Quand une feature devient plugin, on retire son `if
  enable*Feature` correspondant.
- `tabOrder` dans le coordinator : le calcul de direction de transition
  (`tabSwitchForward`) doit gérer `case plugin` — l'ordre des onglets plugin vient de
  `allPlugins`. À traiter via une fonction d'indexation unifiée (legacy + plugins).

### 4.2 Réglages

- `SettingsView` construit sa sidebar depuis l'enum `SettingsTab` + groupes. On ajoute une
  boucle sur `PluginHost.shared.settingsPlugins`, chacun apportant son `settingsGroup` + sa
  vue via `makeSettingsView()`.
- Les `SettingsTab` non migrés restent ; on en retire un à chaque migration de feature.
- Cible à terme : la sidebar Paramètres devient majoritairement data-driven, ce qui résout
  l'incohérence actuelle de répartition manuelle.

### 4.3 Sneak peek / notch fermé

- `SneakContentType` (défini dans `DynamicIslandViewCoordinator.swift:23`) gagne **un seul**
  case générique : `case plugin(id: PluginID, payload: …)`. Penser à étendre l'opérateur
  `==` custom (lignes 43-69) pour ce case.
- Un `SneakPeekProviding` pousse via `PluginHost.shared.surface(_:from:)`, qui relaie au
  coordinator. Le pipeline existant `agentAttention` sert de modèle de référence.

### 4.4 Cycle de vie / service de fond

- Au lancement, `DynamicIslandApp` / `DynamicNotchApp` appelle
  `PluginHost.shared.bootstrap()`.
- Les managers singletons existants (ex. `MacshotManager`) ne changent pas : c'est
  `activate()` du plugin qui les démarre, enregistre l'item menu-bar et les raccourcis ; et
  `deactivate()` qui les arrête.

---

## 5. Le pilote : Screenshot (macshot)

Objectif : valider 3 des 4 surfaces (réglages + cycle de vie + résultat sur notch/shelf)
sans toucher de code stable. Screenshot **ne déclare pas** `NotchTabProviding` — c'est le
signal voulu : un plugin ne déclare que ce qu'il utilise.

### 5.1 Ce que fait `ScreenshotPlugin`

| Aspect | Détail |
|---|---|
| Noyau | `id = "screenshot"`, `displayName`, `icon` (SF Symbol caméra/capture), `defaultsEnableKey = .enableScreenshotFeature` (`Constants.swift:1051`). |
| `SettingsProviding` | `settingsGroup = .utilities` (ou groupe choisi) ; `makeSettingsView()` renvoie `CaptureSettingsView` (existant, `components/Settings/CaptureSettingsView.swift`). |
| `PluginLifecycle` | `activate()` démarre `MacshotManager` et enregistre `ScreenCaptureMenuButton` (item menu-bar, `components/Notch/ScreenCaptureMenuButton.swift`) + raccourcis. `deactivate()` les retire. |
| Résultat capture | À l'issue d'une capture, le résultat est routé vers le **shelf** via `ShelfStateViewModel` (jamais `TrayDrop`, cf. `CLAUDE.md` / mémoire `shelf-two-stores`). Optionnellement émettre un sneak peek via le host pour confirmer visuellement. |

### 5.2 Critère de réussite du pilote

- Le toggle d'activation capture, depuis Paramètres, démarre/arrête réellement le service
  via `activate()`/`deactivate()` (vérifiable : l'item menu-bar apparaît/disparaît).
- La section capture s'affiche dans la sidebar Paramètres **via le host**, plus via un
  `SettingsTab` codé en dur.
- Une capture aboutit dans le shelf comme avant.
- `xcodebuild` reste vert ; l'app tourne (vérif visuelle = demander à Thibault de regarder
  son notch, cf. `CLAUDE.md`).

---

## 6. Migration des autres features (post-pilote)

Une fois le pilote validé, chaque feature suit le même gabarit, dans des chantiers séparés,
par ordre de risque croissant :

1. **Todo** — simple, récent ; exerce onglet + réglages + cycle de vie léger.
2. **Timer** — exerce les 4 surfaces (onglet, sneak peek, réglages, window managers) ;
   première validation complète du contrat sur du code stable.
3. **Stats / ColorPicker / Clipboard / Notes / Terminal** — au fil de l'eau.
4. **Agents** — la plus riche (lifecycle SPM AgentBridge, sockets, sneak peek attention,
   grille, réglages) ; en dernier, une fois le modèle éprouvé.

À chaque migration : créer `Plugins/<Feature>/<Feature>Plugin.swift`, l'ajouter à
`allPlugins`, retirer les entrées legacy correspondantes (case dédié dans `NotchViews` si
présent, `if enable*` dans `TabSelectionView`, `SettingsTab`), vérifier build + run.

**Home** reste hors plugin (c'est le conteneur de base du notch ouvert).

---

## 7. Vérification

Conformément à `CLAUDE.md` :

- `xcodebuild` est la source de vérité (les diagnostics SourceKit « Cannot find type » sont
  du bruit d'index). Build en arrière-plan avec les flags du `CLAUDE.md`.
- Pas de suite de tests ni de linter câblés : vérification = `xcodebuild` vert + app qui
  tourne (ad-hoc sign puis `open`).
- Vérif visuelle du notch : **demander à Thibault** (Claude ne peut pas screenshoter l'app
  agent `LSUIElement`).
- Garde-fou de build : `macshot/` est tiré dans le build par le synchronized-group et a
  déjà cassé le target par le passé — confirmer qu'il compile avant d'incriminer une autre
  modif.

---

## 8. Risques et points de vigilance

| Risque | Mitigation |
|---|---|
| Coexistence legacy/plugin double l'affichage d'un onglet ou d'une section | Discipline : retirer l'entrée legacy **dans le même commit** que l'ajout du plugin correspondant. |
| `case plugin(PluginID)` casse les `switch` exhaustifs sur `NotchViews`/`SneakContentType` | Recenser tous les `switch` sur ces enums et ajouter le case ; le compilateur les signale (atout). |
| `@MainActor` / concurrence | Host et capacités UI annotés `@MainActor` ; cohérent avec les managers existants (`@MainActor ObservableObject`). |
| `AnyView` (effacement de type) coûte un peu en perf SwiftUI | Acceptable au nombre de plugins concerné ; alternative `@ViewBuilder` générique écartée pour garder un registre hétérogène simple. |
| Ordre d'activation au bootstrap | `allPlugins` fixe l'ordre déterministe ; documenter toute dépendance inter-plugin (à éviter — les plugins doivent rester indépendants). |

---

## 9. Résumé

On introduit une fine couche `Plugins/Core` (protocole noyau + 4 protocoles de capacité +
un host `@MainActor`) interne au target `DynamicIsland`. Le host est **additif** : il
alimente `TabSelectionView`, `SettingsView` et le pipeline sneak peek existants via deux
cases génériques (`NotchViews.plugin`, `SneakContentType.plugin`), sans casser les features
non migrées. On valide le modèle sur le pilote **Screenshot**, puis on migre les autres
features une par une, du plus simple (Todo) au plus complexe (Agents), en retirant le code
legacy au fur et à mesure. À la fin, ajouter une feature ne touche plus qu'**un** endroit :
`PluginHost.allPlugins`.
