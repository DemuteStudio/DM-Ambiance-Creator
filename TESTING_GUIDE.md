# DM Ambiance Creator - Guide de Test du Système Folders

## 🎯 Objectif des Tests
Valider le système de Folders récursifs dans REAPER, incluant la création, l'organisation, la génération et la compatibilité ascendante.

---

## 📋 Checklist de Test Complète

### ✅ Phase 1 : Démarrage et Migration (5 min)

#### Test 1.1 : Premier Lancement (Nouveau Projet)
- [✅] Lancer REAPER avec un nouveau projet vide
- [✅] Lancer "DM_Ambiance Creator" depuis Actions
- [✅] **Vérifier** : La fenêtre s'ouvre sans erreurs
- [✅] **Vérifier** : Panneau gauche vide (aucun group/folder)
- [✅] **Vérifier** : Boutons visibles : `[Add Group]` `[Add Folder]`

#### Test 1.2 : Migration Projet Existant
- [✅] Ouvrir un projet REAPER avec des ambiances créées AVANT l'implémentation folders
- [✅] Lancer "DM_Ambiance Creator"
- [✅] **Vérifier** : Console REAPER affiche "Migrated old groups structure" (si anciens groups existent)
- [✅] **Vérifier** : Tous les groups existants sont visibles dans le panneau gauche
- [?] **Vérifier** : Les groups ont tous un type `"group"` (invisible pour l'utilisateur)
- [✅] **Vérifier** : Génération fonctionne comme avant (backward compatibility)

---

### ✅ Phase 2 : Création de Folders (10 min)

#### Test 2.1 : Créer un Folder au Top-Level
- [✅] Cliquer sur `[Add Folder]`
- [✅] **Vérifier** : Un nouveau folder apparaît avec icône 📁
- [✅] **Vérifier** : Nom par défaut : "New Folder"
- [✅] **Vérifier** : Boutons visibles : `[▼]` `[+Group]` `[+Folder]` `[Delete]`
- [X] Renommer le folder en "Ambiance Extérieure"
- [ ] **Vérifier** : Le nom change immédiatement

#### Test 2.2 : Créer un Group dans un Folder
- [ ] Cliquer sur l'icône `[▼]` du folder pour l'expandre (si collapsed)
- [ ] Cliquer sur `[+Group]` DANS le folder
- [ ] **Vérifier** : Un nouveau group apparaît INDENTÉ sous le folder
- [ ] **Vérifier** : Le group n'a PAS d'icône folder (ou icône 📦 si implémenté)
- [ ] Renommer le group en "Oiseaux"
- [ ] Ajouter un container "Merle" avec un fichier audio bird.wav

#### Test 2.3 : Créer un Folder dans un Folder (Récursion)
- [ ] Dans "Ambiance Extérieure", cliquer sur `[+Folder]`
- [ ] **Vérifier** : Un sous-folder apparaît indenté
- [ ] Renommer en "Forêt"
- [ ] Dans "Forêt", créer un group "Vent"
- [ ] **Vérifier** : Indentation correcte (3 niveaux visibles)

#### Test 2.4 : Créer des Groups Standalone
- [ ] Au top-level, cliquer sur `[Add Group]` (PAS dans un folder)
- [ ] **Vérifier** : Le group apparaît au même niveau que les folders
- [ ] Renommer en "Ambiance Intérieure"
- [ ] **Vérifier** : Hiérarchie mixte :
  ```
  📁 Ambiance Extérieure
    📁 Forêt
      📊 Vent
    📊 Oiseaux
  📊 Ambiance Intérieure
  ```

---

### ✅ Phase 3 : Sélection et Édition (10 min)

#### Test 3.1 : Sélection de Folder
- [ ] Cliquer sur le folder "Ambiance Extérieure"
- [ ] **Vérifier** : Le folder est surligné (sélection active)
- [ ] **Vérifier** : Panneau droit affiche "Folder Settings"
- [ ] **Vérifier** : 4 contrôles visibles :
  - [ ] Name input
  - [ ] Volume slider (-144 dB à +24 dB)
  - [ ] Solo checkbox
  - [ ] Mute checkbox
- [ ] **Vérifier** : Info affichée : "Contains X item(s)"

#### Test 3.2 : Éditer Volume Folder
- [ ] Modifier le volume slider à -6 dB
- [ ] **Vérifier** : La valeur change immédiatement
- [ ] Générer l'ambiance (voir Phase 4)
- [ ] **Vérifier** : Le folder track dans REAPER a un volume de -6 dB

#### Test 3.3 : Solo/Mute Folder
- [ ] Cocher "Solo" sur un folder
- [ ] Générer
- [ ] **Vérifier** : Le folder track REAPER est en solo (bouton S actif)
- [ ] Décocher Solo, cocher "Mute"
- [ ] Générer
- [ ] **Vérifier** : Le folder track REAPER est mute (bouton M actif)

#### Test 3.4 : Sélection de Group
- [ ] Cliquer sur un group "Oiseaux"
- [ ] **Vérifier** : Le panneau droit affiche les paramètres du group (trigger, randomization, etc.)
- [ ] **Vérifier** : PAS les paramètres folder (pas de solo/mute au niveau group dans ce système)

#### Test 3.5 : Sélection de Container
- [ ] Cliquer sur un container
- [ ] **Vérifier** : Le panneau droit affiche les paramètres container
- [ ] **Vérifier** : Comportement identique à avant folders

---

### ✅ Phase 4 : Génération REAPER (15 min)

#### Test 4.1 : Génération avec `generateFolderTracks = true` (Default)
- [ ] Ouvrir Settings (icône engrenage)
- [ ] **Vérifier** : Section "REAPER Track Generation" visible
- [ ] **Vérifier** : "Generate folder tracks in REAPER" est COCHÉ (default)
- [ ] Fermer Settings
- [ ] Créer une time selection (1-10 secondes)
- [ ] Cliquer sur "Generate"
- [ ] **Vérifier** : Dans REAPER Track View :
  ```
  📁 Ambiance Extérieure (folder track)
  ├─ 📁 Forêt (folder track)
  │  └─ Vent (group track)
  │     └─ Container tracks...
  └─ Oiseaux (group track)
      └─ Container tracks...
  📊 Ambiance Intérieure (group track, pas de folder parent)
     └─ Container tracks...
  ```

#### Test 4.2 : Vérifier I_FOLDERDEPTH
- [ ] Sélectionner le folder track "Ambiance Extérieure"
- [ ] Ouvrir Track Properties (Alt+Enter ou double-clic)
- [ ] **Vérifier** : Folder Depth = 1 (c'est un folder parent)
- [ ] Sélectionner le dernier track enfant (dernier container track)
- [ ] **Vérifier** : Folder Depth = -1 (ferme le folder)
- [ ] Pour folders imbriqués, dernier track devrait avoir -2 (ferme 2 folders)

#### Test 4.3 : Vérifier Propriétés Folder Tracks
- [ ] Sélectionner folder track avec volume -6 dB
- [ ] **Vérifier** : Volume fader du track = -6 dB
- [ ] Sélectionner folder track avec Solo activé
- [ ] **Vérifier** : Bouton S (Solo) est actif sur le track
- [ ] Sélectionner folder track avec Mute activé
- [ ] **Vérifier** : Bouton M (Mute) est actif sur le track

#### Test 4.4 : Folder Vide
- [ ] Créer un folder sans aucun group enfant
- [ ] Générer
- [ ] **Vérifier** : Un track enfant "(empty)" est créé sous le folder
- [ ] **Vérifier** : Pas d'erreur, pas de crash

#### Test 4.5 : Génération avec `generateFolderTracks = false`
- [ ] Ouvrir Settings
- [ ] DÉCOCHER "Generate folder tracks in REAPER"
- [ ] Fermer Settings et sauvegarder
- [ ] Supprimer les tracks existants dans REAPER
- [ ] Cliquer sur "Generate"
- [ ] **Vérifier** : Aucun folder track n'est créé
- [ ] **Vérifier** : Seuls les group tracks et container tracks sont créés
- [ ] **Vérifier** : Structure plate dans REAPER (pas de hiérarchie folder)
- [ ] **Vérifier** : L'UI de DM Ambiance Creator affiche toujours les folders (organisation UI uniquement)

#### Test 4.6 : Imbrication Profonde (5+ Niveaux)
- [ ] Créer : Folder → Folder → Folder → Folder → Group → Container
- [ ] Générer avec folders activés
- [ ] **Vérifier** : Tous les folders sont créés avec bonne hiérarchie
- [ ] **Vérifier** : Le dernier track a `I_FOLDERDEPTH = -4` ou moins (ferme tous les folders)

---

### ✅ Phase 5 : Drag & Drop (10 min)

#### Test 5.1 : Drag Folder dans Folder
- [ ] Créer 2 folders au top-level : "Folder A" et "Folder B"
- [ ] Drag "Folder A" et drop sur "Folder B"
- [ ] **Vérifier** : "Folder A" devient enfant de "Folder B"
- [ ] **Vérifier** : Indentation correcte dans l'UI

#### Test 5.2 : Drag Group dans Folder
- [ ] Créer un group standalone "Group X"
- [ ] Drag "Group X" et drop dans un folder
- [ ] **Vérifier** : "Group X" devient enfant du folder
- [ ] **Vérifier** : Le group n'est plus au top-level

#### Test 5.3 : Drag Group hors Folder
- [ ] Drag un group depuis un folder vers le top-level (drop entre 2 items top-level)
- [ ] **Vérifier** : Le group devient standalone
- [ ] **Vérifier** : Le group n'est plus dans le folder

#### Test 5.4 : Drag Container entre Groups
- [ ] Créer 2 groups dans 2 folders différents
- [ ] Drag un container du Group A vers le Group B
- [ ] **Vérifier** : Le container change de parent
- [ ] **Vérifier** : Fonctionne même si groups dans folders différents

#### Test 5.5 : Drop Positioning (Before/After/Into)
- [ ] Drag un folder et observer les zones de drop :
  - [ ] Drop AU-DESSUS d'un item (ligne bleue au-dessus) → insère avant
  - [ ] Drop EN-DESSOUS d'un item (ligne bleue en-dessous) → insère après
  - [ ] Drop SUR un folder (highlight complet) → insère dedans
- [ ] Tester chaque cas
- [ ] **Vérifier** : Positionnement correct après drop

#### Test 5.6 : Validation Drag & Drop
- [ ] Tenter de drag un folder dans lui-même
- [ ] **Vérifier** : Drop refusé (pas de boucle infinie)
- [ ] Tenter de drag un folder dans un de ses descendants
- [ ] **Vérifier** : Drop refusé (empêche récursion circulaire)
- [ ] Tenter de drag un container directement dans un folder (pas dans un group)
- [ ] **Vérifier** : Drop refusé (containers doivent être dans groups)

---

### ✅ Phase 6 : Context Menus et Actions (10 min)

#### Test 6.1 : Copy/Paste Folder
- [ ] Clic droit sur un folder
- [ ] Sélectionner "Copy"
- [ ] Clic droit dans zone vide ou autre folder
- [ ] Sélectionner "Paste"
- [ ] **Vérifier** : Le folder est dupliqué avec tous ses enfants (récursif)
- [ ] **Vérifier** : Nom ajusté ("Folder (Copy)" si déjà existant)

#### Test 6.2 : Duplicate Folder
- [ ] Clic droit sur un folder
- [ ] Sélectionner "Duplicate"
- [ ] **Vérifier** : Copie immédiate créée avec nom "(Copy)"
- [ ] **Vérifier** : Tous les children sont dupliqués

#### Test 6.3 : Delete Folder
- [ ] Clic droit sur un folder avec plusieurs groups enfants
- [ ] Sélectionner "Delete"
- [ ] **Vérifier** : Confirmation popup (si implémenté)
- [ ] Confirmer
- [ ] **Vérifier** : Le folder ET tous ses enfants sont supprimés

#### Test 6.4 : Copy/Paste Group (dans folders)
- [ ] Copy un group depuis un folder
- [ ] Paste dans un autre folder
- [ ] **Vérifier** : Le group est copié dans le nouveau folder
- [ ] **Vérifier** : L'original reste dans le folder source

#### Test 6.5 : Delete Group dans Folder
- [ ] Supprimer un group qui est dans un folder
- [ ] **Vérifier** : Le group disparaît
- [ ] **Vérifier** : Le folder parent reste intact
- [ ] **Vérifier** : Les autres groups du folder ne sont pas affectés

---

### ✅ Phase 7 : Presets (15 min)

#### Test 7.1 : Sauvegarder Global Preset avec Folders
- [ ] Créer hiérarchie complexe :
  ```
  📁 Folder A
    📁 Folder B
      📊 Group X
    📊 Group Y
  📊 Group Z
  ```
- [ ] Cliquer sur "Save Preset" (global)
- [ ] Nommer "Test_Folders_Preset"
- [ ] **Vérifier** : Message "Preset saved successfully"
- [ ] **Vérifier** : Fichier créé dans `/Presets/Global/Test_Folders_Preset.lua`

#### Test 7.2 : Charger Global Preset avec Folders
- [ ] Supprimer tous les items dans l'UI
- [ ] Charger "Test_Folders_Preset"
- [ ] **Vérifier** : Hiérarchie complète restaurée
- [ ] **Vérifier** : Tous les folders, groups, containers présents
- [ ] **Vérifier** : Indentation correcte
- [ ] **Vérifier** : Propriétés préservées (volumes, solo, mute)

#### Test 7.3 : Charger Ancien Preset (Sans Folders)
- [ ] Créer un preset AVANT l'implémentation folders (ou simuler)
  - Preset contient seulement groups sans champ `type`
- [ ] Charger ce preset
- [ ] **Vérifier** : Console REAPER affiche "Migrated old preset format"
- [ ] **Vérifier** : Les groups apparaissent au top-level (standalone)
- [ ] **Vérifier** : Les groups ont type="group" ajouté automatiquement
- [ ] **Vérifier** : Génération fonctionne normalement

#### Test 7.4 : Group Preset depuis Folder
- [ ] Sélectionner un group qui est DANS un folder
- [ ] Sauvegarder comme "Group Preset"
- [ ] **Vérifier** : Preset sauvegardé dans `/Presets/Groups/`
- [ ] Supprimer le group
- [ ] Charger le "Group Preset"
- [ ] **Vérifier** : Le group est restauré dans le même folder

#### Test 7.5 : Container Preset depuis Group dans Folder
- [ ] Sélectionner un container dans un group dans un folder
- [ ] Sauvegarder comme "Container Preset"
- [ ] Charger dans un autre group (même folder ou autre)
- [ ] **Vérifier** : Container copié avec ses paramètres

---

### ✅ Phase 8 : Multi-Selection (5 min)

#### Test 8.1 : Multi-Selection avec Ctrl+Click
- [ ] Cliquer sur un container
- [ ] Ctrl+Click sur 2 autres containers (dans différents groups/folders)
- [ ] **Vérifier** : Les 3 containers sont sélectionnés (highlights)
- [ ] Drag vers un autre group
- [ ] **Vérifier** : Les 3 containers se déplacent ensemble

#### Test 8.2 : Range Selection avec Shift+Click
- [ ] Cliquer sur un container
- [ ] Shift+Click sur un container 5 positions plus bas
- [ ] **Vérifier** : Tous les containers entre les 2 sont sélectionnés
- [ ] **Vérifier** : Fonctionne même à travers plusieurs groups/folders

---

### ✅ Phase 9 : Undo/Redo (5 min)

#### Test 9.1 : Undo Création Folder
- [ ] Créer un nouveau folder
- [ ] Cliquer sur bouton Undo (ou Ctrl+Z si implémenté)
- [ ] **Vérifier** : Le folder disparaît
- [ ] Cliquer sur Redo
- [ ] **Vérifier** : Le folder réapparaît

#### Test 9.2 : Undo Génération avec Folders
- [ ] Générer avec folders activés
- [ ] Dans REAPER : Edit → Undo (Ctrl+Z)
- [ ] **Vérifier** : Tous les tracks générés disparaissent
- [ ] Redo (Ctrl+Shift+Z)
- [ ] **Vérifier** : Tracks réapparaissent avec hiérarchie correcte

---

### ✅ Phase 10 : Edge Cases et Robustesse (10 min)

#### Test 10.1 : Folder avec 100+ Groups
- [ ] Créer un folder
- [ ] Ajouter 100 groups dedans (scripter si possible)
- [ ] **Vérifier** : UI reste responsive
- [ ] Générer
- [ ] **Vérifier** : Pas de crash, génération complète

#### Test 10.2 : Imbrication 10+ Niveaux
- [ ] Créer 10 folders imbriqués : Folder → Folder → ... → Group
- [ ] Générer
- [ ] **Vérifier** : Hiérarchie REAPER correcte
- [ ] **Vérifier** : Dernier track a `I_FOLDERDEPTH` très négatif

#### Test 10.3 : Renommer pendant Génération
- [ ] Lancer génération
- [ ] Pendant que ça génère, renommer un folder
- [ ] **Vérifier** : Pas de crash
- [ ] **Vérifier** : Comportement prévisible (change avant ou après selon timing)

#### Test 10.4 : Suppression Multiple
- [ ] Multi-sélectionner 5 items (mix folders et groups)
- [ ] Supprimer tous
- [ ] **Vérifier** : Tous les items et leurs enfants supprimés
- [ ] **Vérifier** : Sélection correctement cleared

#### Test 10.5 : Fermer et Rouvrir REAPER
- [ ] Créer hiérarchie complexe avec folders
- [ ] Sauvegarder projet REAPER
- [ ] Fermer REAPER complètement
- [ ] Rouvrir projet
- [ ] Relancer DM Ambiance Creator
- [ ] **Vérifier** : Hiérarchie restaurée (si sauvegardée dans project)
- [ ] **Note** : Actuellement globals n'est pas persisté, seulement les tracks REAPER

---

## 🐛 Checklist de Bugs Connus à Vérifier

### Bugs Potentiels
- [ ] **Drag circulaire** : Folder A dans Folder B, puis Folder B dans Folder A
- [ ] **Path invalidation** : Supprimer un folder pendant qu'un child est sélectionné
- [ ] **Container key parsing** : Clés avec underscores dans paths longs
- [ ] **I_FOLDERDEPTH overflow** : Plus de 127 niveaux imbriqués (limite REAPER)
- [ ] **Unicode names** : Folders avec emojis ou caractères spéciaux
- [ ] **Empty folder generation** : Dummy track créé mais jamais supprimé

### Performance
- [ ] **Large hierarchy** : 1000+ folders/groups (latence UI ?)
- [ ] **Deep recursion** : 50+ niveaux (stack overflow ?)
- [ ] **Rapid clicks** : Spam "Add Folder" 100x rapidement

---

## 📊 Résultats Attendus

### ✅ Succès Global
Tous les tests passent sans erreur ni crash. Les folders s'intègrent naturellement dans le workflow existant.

### ⚠️ Warnings Acceptables
- Console messages pour migration (informatif)
- Ralentissement léger avec 1000+ items (acceptable)

### ❌ Failures Critiques
- Crash pendant génération
- Perte de données (folders/groups disparus)
- Corruption de hiérarchie (folders mal imbriqués)
- Incompatibilité presets anciens (ne chargent pas)

---

## 🔧 Procédure de Debug

Si un test échoue :

1. **Console REAPER** : Vérifier messages d'erreur
2. **Lua logs** : Activer debug mode (si disponible)
3. **_G.globals** : Inspecter via REAPER console :
   ```lua
   _G.globals.items  -- Vérifier structure
   _G.globals.selectedPath  -- Vérifier sélection
   ```
4. **Track Properties** : Vérifier I_FOLDERDEPTH manuellement
5. **Preset Files** : Ouvrir `/Presets/Global/*.lua` et vérifier syntaxe

---

## ✅ Validation Finale

**Le système est prêt pour production si :**
- ✅ 90%+ des tests passent
- ✅ Aucun bug critique
- ✅ Performance acceptable (< 1s pour génération 100 groups)
- ✅ Backward compatibility vérifiée
- ✅ Presets chargent correctement

**Durée totale des tests : ~1h30 - 2h**

---

Bon test ! 🎵🚀
