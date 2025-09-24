# Multi-Channel Support - Corrections Apportées

## Problèmes Identifiés et Corrigés

### 1. ✅ Hiérarchie des tracks
**Problème**: Les tracks créées n'étaient pas enfants de la track container
**Solution**: Corrigé l'insertion des tracks avec `reaper.InsertTrackAtIndex(containerIdx + i, false)` au lieu de `true`

### 2. ✅ Simplification de la distribution
**Problème**: Les modes de distribution n'étaient pas utiles
**Solution**:
- Supprimé la propriété `channelDistribution` des containers
- Supprimé l'UI pour la sélection du mode de distribution
- Modifié la génération pour créer indépendamment les items sur chaque track avec les mêmes paramètres

### 3. ✅ Régénération multi-channel
**Problème**: La régénération ne respectait pas la structure multi-channel avec "Keep existing tracks"
**Solution**:
- Modifié `generateSingleContainer` pour utiliser `getExistingChannelTracks` et `clearChannelTracks`
- Corrigé l'incohérence entre `overrideExistingTracks` et `keepExistingTracks`

### 4. ✅ Labels des canaux Quad
**Problème**: Le mode Quad avait "Rear Center" au lieu des bons labels
**Solution**: Corrigé les labels en "Front L", "Front R", "Rear L", "Rear R"

### 5. ✅ Routing et nombre de canaux
**Problème**:
- Le parent n'avait pas le bon nombre de canaux
- Les sends des tracks enfants étaient mal configurés
**Solution**:
- Parent configuré avec `channels * 2` (ex: Quad = 8 canaux)
- Routing simplifié: Track 1 → Canaux 1/2, Track 2 → Canaux 3/4, etc.
- Ajout du gain unity (1.0) sur les sends

## Fichiers Modifiés

1. **DM_Ambiance_Constants.lua**
   - Correction des labels Quad

2. **DM_Ambiance_Structures.lua**
   - Suppression de `channelDistribution`

3. **DM_Ambiance_Utils.lua**
   - Correction du calcul des canaux du parent (`channels * 2`)

4. **DM_Ambiance_Generation.lua**
   - Fix de l'insertion des tracks enfants
   - Simplification du routing
   - Nouvelle logique de génération (indépendante par track)
   - Correction de la régénération

5. **DM_Ambiance_UI_Container.lua**
   - Suppression de l'UI pour la distribution

## Nouveau Comportement

### Génération Multi-Channel
1. Le container devient un folder avec N tracks enfants
2. Chaque track enfant génère ses propres items avec les mêmes paramètres
3. Les items sont placés indépendamment sur chaque canal (pas de distribution)

### Structure des Tracks
```
Container (Folder) - 8 canaux pour Quad, 10 pour 5.0, etc.
├── Container - Front L (Send → 1/2)
├── Container - Front R (Send → 3/4)
├── Container - Rear L (Send → 5/6)
└── Container - Rear R (Send → 7/8)
```

### Régénération
- Si "Keep existing tracks" est activé: préserve la structure multi-channel
- Seuls les items sont supprimés et régénérés
- Le changement de mode recrée la structure si nécessaire

## Tests Recommandés

1. **Création**: Tester chaque mode (Default, 4.0, 5.0, 5.1, 7.1)
2. **Hiérarchie**: Vérifier que les tracks sont bien enfants du container
3. **Routing**: Vérifier les sends dans le routing matrix de Reaper
4. **Régénération**: Tester avec "Keep existing tracks" activé/désactivé
5. **Changement de mode**: Passer d'un mode à l'autre et régénérer

## Notes Importantes

- La génération est maintenant plus simple: chaque track génère la même séquence avec randomisation indépendante
- Les paramètres de pan/volume par canal sont toujours disponibles pour ajuster le mixage
- Le mode Default reste inchangé (rétrocompatibilité préservée)