# Spec — Tab « Apps » + grille de lancement façon iPhone

Date : 2026-06-09 (révisée — remplace l'approche « More → popover »)
Statut : proposé (en attente de validation)

## 1. Problème

L'en-tête de l'encoche ouverte déborde silencieusement quand trop de features/plugins sont actifs :

- **Barre gauche — navigation** (`TabSelectionView`) : Home, Shelf, Timer, Stats, Notes/Clipboard, Terminal + tabs de plugins (Todo, Agents, Weather) + extensions. `HStack(spacing: 24)` borné à gauche de l'encoche physique → plafond ~5, le reste est rogné.
- **Barre droite — actions rapides** (inline dans `DynamicIslandHeader`) : mirror, clipboard, color picker, timer, screenshot, gear + indicateurs statut (recording/DND) + batterie. `HStack(spacing: 4)` borné à droite, même débordement.

Chaque tab est **icône seule** (`TabButton` ne rend que `Image(systemName:)`).

## 2. Concept retenu

On garde la structure actuelle (barre gauche de navigation, cluster d'actions en haut à droite), mais on ajoute **un seul élément structurant** :

> **Un tab « Apps » toujours visible.** Un clic ouvre une **grille façon écran d'accueil iPhone** listant *tous* les plugins/features/extensions disponibles. C'est le réceptacle canonique et complet : la barre gauche n'est plus qu'un raccourci vers les favoris ; la grille contient tout. Les **actions rapides** restent en haut à droite, personnalisables, et **celles qui ne tiennent pas basculent dans la grille**.

Analogie Apple : la barre gauche = le **Dock**, la grille « Apps » = l'**écran d'accueil / App Library**. Plus de rognage, scalabilité illimitée, geste familier.

## 3. Décisions de conception (à valider)

1. **La grille « Apps » est exhaustive.** Elle affiche **toutes** les destinations activées (y compris celles déjà épinglées dans la barre). Mental model simple : « Apps = tout ». Pas de logique « retirer de la grille si dans le Dock ».
2. **Le tab « Apps » est toujours visible**, position fixe en **dernier slot de la barre gauche** (le plus proche de l'encoche). Les favoris remplissent les slots avant lui ; ceux qui ne tiennent pas ne s'affichent pas dans la barre mais restent dans la grille.
3. **Statut & batterie jamais en overflow.** Recording, DND et batterie restent ancrés à l'extrême droite. Seules les *actions* personnalisables peuvent basculer dans la grille.
4. **Overflow = grille, pas de popover.** Ni à gauche ni à droite il n'y a de mini-popover : tout débordement retombe dans la grille « Apps ». Un seul réceptacle.
5. **Rétro-compatible, zéro migration.** Ordre des favoris vide = ordre par défaut actuel → out of the box l'app ressemble à aujourd'hui, +1 tab « Apps », et le débordement a enfin un foyer.

## 4. Modèle unifié

Une seule source de vérité alimente *à la fois* les barres et la grille, pour qu'elles soient cohérentes.

```swift
struct LauncherItem: Identifiable {
    enum Kind { case destination, action }
    let id: String          // identité stable (clé d'ordre/épinglage)
    let kind: Kind
    let icon: String        // SF Symbol
    let label: String       // tuile de grille + VoiceOver
    var accentColor: Color?
    var badge: Int?
    var isSelected: Bool     // destinations : vue active
    let activate: () -> Void // destination → currentView = … ; action → toggle/capture
}
```

- **Destinations** = tout ce qui est sélectionnable comme vue (tabs système actuels + tabs de plugins + tabs d'extensions). IDs réutilisent ceux déjà stables de `TabModel`.
- **Actions** = le cluster droit actuel, chacune avec un **ID stable** (`action-clipboard`, `action-colorpicker`, `action-timer`, `action-screenshot`, `action-mirror`, `action-settings`).
- Statut (recording/DND) + batterie **ne** sont **pas** des `LauncherItem` : rendus à part, en accessoire de fin de barre droite.

### Registre central — `NotchLauncherModel` (@MainActor ObservableObject)

Construit et expose les listes ordonnées, en appliquant ordre + épinglage utilisateur :

```swift
var destinations: [LauncherItem]   // toutes activées, épinglées d'abord puis le reste
var quickActions: [LauncherItem]   // toutes activées, dans l'ordre utilisateur
```

Le découpage « ce qui tient dans la barre / ce qui passe en grille » est fait **dans les vues** (elles connaissent leur largeur via `GeometryReader`). Le modèle ne fait que fournir des listes ordonnées + l'info d'épinglage. C'est l'unique endroit où l'ordre est défini → barre et grille ne peuvent pas diverger.

## 5. Composition des barres

### Barre gauche (navigation)
`favoris qui tiennent (ordre utilisateur) + tab « Apps » (toujours, dernier slot)`.

- Largeur de slot fixe (≈ 26pt) → capacité = `floor((width + spacing) / (slot + spacing))`, en réservant 1 slot pour « Apps ».
- Tab « Apps » : glyphe grille (`square.grid.2x2.fill`), `activate` = `currentView = .apps`.
- `TabButton` réutilisé pour chaque slot.

### Barre droite (actions rapides)
`actions qui tiennent (ordre utilisateur) + accessoire statut/batterie (fixe, extrême droite)`.

- Capacité calculée pareil ; les actions en trop **ne** sont **pas** rendues ici → elles apparaissent dans une section de la grille (§6).
- Aucune action n'évince jamais le statut/batterie.

## 6. La grille « Apps » — cœur UX (digne d'Apple)

Nouvelle vue `currentView = .apps` → `AppsGridView`, rendue dans la zone de contenu de l'encoche ouverte (même surface que Stats/Notes aujourd'hui).

### Structure
- **Section « Apps »** : toutes les destinations, en tuiles.
- **Section « Actions rapides »** (n'apparaît que si des actions ont débordé) : titre discret + les actions repliées, mêmes tuiles.
- Une seule page qui tient dans la hauteur ouverte ; si ça dépasse, **scroll vertical** doux. (Pagination horizontale à points = polish optionnel, hors v1.)

### Tuile `AppTile` (squircle façon iOS)
- `RoundedRectangle(cornerRadius: 14, style: .continuous)`, ≈ 52×52pt, rempli d'un fond `accentColor.opacity(0.18)` sur un `.ultraThinMaterial`, fine bordure `white.opacity(0.06)`.
- SF Symbol centré ≈ 22pt, teinté accent (ou blanc selon contraste).
- **Label** dessous : `.caption2`, secondaire, 1 ligne, truncation par milieu.
- **Badge** en haut-droite de la tuile (capsule rouge, réutilise le style existant) ; ex. compteur Todo.
- État sélectionné (destination active) : anneau/halo accent subtil autour de la tuile.

### Layout
- `LazyVGrid(columns: adaptive(min: 64), spacing: 16)`, padding cohérent avec les autres vues de contenu.
- 4 colonnes nominales sur l'encoche ouverte standard ; s'adapte si plus étroit.

### Mouvement (Apple-grade, respecte Reduce Motion)
- **Ouverture** : tuiles en apparition décalée (stagger ~0.02s), `scale 0.9→1 + opacity` en spring doux.
- **Press** : tuile `scale 0.92` spring pendant l'appui (feedback haptique-like visuel).
- **Sélection destination** : `activate()` → `currentView` change ; transition douce vers la vue cible (réutilise l'anim de switch de tab existante).
- **Sélection action** : exécute l'action (toggle popover/panneau, capture). Pour les actions qui ouvrent leur propre popover, il s'ancre à son bouton d'origine s'il est visible, sinon au tab « Apps » (détail d'ancrage à l'implémentation — risque mineur §9).
- `@Environment(\.accessibilityReduceMotion)` → désactive stagger/scale, simple fondu.

### Navigation depuis la grille
- Sélectionner une destination non épinglée bascule la vue ; le tab « Apps » reste l'indicateur d'origine contextuel (la vue ouverte affiche elle-même son titre). Promotion temporaire de la destination active dans un slot de barre = polish optionnel, hors v1.

## 7. Persistance & personnalisation

### Defaults (`models/Constants.swift`)
```swift
extension Defaults.Keys {
    static let notchFavoriteDestinations = Key<[String]>("notchFavoriteDestinations", default: []) // ordre des favoris (barre gauche)
    static let notchQuickActionsOrder    = Key<[String]>("notchQuickActionsOrder",    default: []) // ordre des actions (barre droite)
}
```
- Ordre vide ⇒ ordre par défaut du registre (rétro-compatible).
- Nouveaux items (plugin/extension fraîchement activé absent de l'ordre) ⇒ ajoutés **en fin**, non favoris.

### UI Réglages — section « Barre de l'encoche » (`components/Settings/NotchBarSettings.swift`)
Deux listes réordonnables (`List` + `.onMove`) :
- **Favoris (barre gauche)** : icône + libellé + drag handle. L'ordre détermine qui tient dans la barre ; tout reste de toute façon dans la grille.
- **Actions rapides (barre droite)** : icône + libellé + drag handle. Ce qui ne tient pas bascule dans la grille.

Texte d'aide : « Les éléments qui ne tiennent pas dans la barre apparaissent dans Apps. » Pas de live-preview en v1.

## 8. Fichiers touchés

| Fichier | Changement |
|---|---|
| `components/Apps/LauncherItem.swift` *(nouveau)* | Modèle `LauncherItem`. |
| `services/NotchLauncherModel.swift` *(nouveau)* | Registre central : destinations + actions ordonnées (s'appuie sur `PluginHost`). |
| `components/Apps/AppsGridView.swift` *(nouveau)* | Grille + sections + animations. |
| `components/Apps/AppTile.swift` *(nouveau)* | Tuile squircle. |
| `DynamicIslandViewCoordinator.swift` | Ajoute `.apps` à `NotchViews` + `tabOrder`. |
| `components/Tabs/TabSelectionView.swift` | Construit favoris (fit) + tab « Apps » fixe ; consomme `NotchLauncherModel`. |
| `components/Notch/DynamicIslandHeader.swift` | Cluster droit = actions (fit, ordre) + accessoire statut/batterie ; overflow → grille. |
| `ContentView.swift` | Branche `case .apps` → `AppsGridView`. |
| `models/Constants.swift` | 2 clés Defaults. |
| `components/Settings/NotchBarSettings.swift` *(nouveau)* + `SettingsView.swift` | Section de personnalisation. |

## 9. Risques & cas limites
- **Mesure pendant l'anim d'ouverture** : largeur transitoire → animer le nombre de slots visibles, tolérer un reflow d'une frame.
- **Popover d'action lancé depuis la grille** : ancrage à valider (bouton d'origine masqué) — isolé, risque mineur.
- **Hauteur ouverte limitée** : si la grille dépasse, scroll vertical ; vérifier que ça ne casse pas le hover/auto-close de l'encoche.
- **`enableMinimalisticUI`** masque déjà les tabs → tab « Apps » et grille non montés dans ce mode.
- **Capacité barre = 0** (encoche très étroite) : seul le tab « Apps » s'affiche à gauche ; tout est dans la grille. Acceptable, voire idéal.

## 10. Hors périmètre (v1)
- Pagination horizontale à points dans la grille (scroll vertical suffit).
- Drag-and-drop de réorganisation directement dans la grille/encoche (réorg via Réglages uniquement).
- Promotion temporaire de la destination active dans la barre.
- Dossiers / catégories dans la grille.
- Tri intelligent par fréquence d'usage.

## 11. Critère de succès
Build `xcodebuild` vert. Avec 8+ destinations activées : barre gauche = favoris qui tiennent + tab « Apps », aucune icône rognée ; cliquer « Apps » ouvre une grille iPhone-like listant tout, avec badges et animation d'apparition soignée ; sélectionner une tuile bascule la vue. Côté droit : actions personnalisables, celles en trop apparaissent dans la section « Actions rapides » de la grille, batterie toujours à l'extrême droite. L'ordre défini dans les Réglages est respecté.
