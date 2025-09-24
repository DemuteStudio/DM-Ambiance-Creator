# Multi-Channel Support - Corrections Finales Appliquées

## ✅ Problèmes résolus

### 1. Routing mono corrigé
**Problème**: Le routing envoyait en stéréo au lieu de mono vers un canal spécifique
**Solution appliquée**:
```lua
-- Format correct pour routing mono vers mono en Reaper:
local srcChannels = 1024  -- Mode mono (bit 10 = 1)
local dstChannels = 1024 + destChannel  -- Mode mono + numéro du canal
```
- Track enfant L (mono) → Canal 1 du parent
- Track enfant R (mono) → Canal 2 du parent
- Track enfant LS (mono) → Canal 3 du parent
- Track enfant RS (mono) → Canal 4 du parent

### 2. Hiérarchie parent-enfant corrigée
**Problème**: Les tracks n'apparaissaient pas comme enfants du container
**Solution appliquée**:
- Insertion toujours à `containerIdx + 1` pour maintenir la relation parent-enfant
- Container configuré comme folder (depth = 1) AVANT l'insertion des enfants
- Dernière track enfant ferme le folder (depth = -1)
- Ajout de `UpdateArrange()` après création pour forcer la mise à jour

### 3. Régénération corrigée
**Problème**: La régénération ne fonctionnait pas correctement en multi-channel
**Solution appliquée**:
- Détection claire du mode (Default vs Multi-channel)
- Mode Default: nettoyage et génération sur le container lui-même
- Mode Multi-channel: nettoyage et génération sur les tracks enfants
- Gestion du changement de configuration (recréation si nécessaire)

## Structure finale

### Mode Default (Stereo)
```
Container (2 canaux, pas de folder)
└── Items générés directement sur cette track
```

### Mode 4.0 Quad
```
Container (4 canaux, folder)
├── Container - L (mono → canal 1)
├── Container - R (mono → canal 2)
├── Container - LS (mono → canal 3)
└── Container - RS (mono → canal 4)
    └── Items générés sur chaque track enfant
```

### Mode 5.0
```
ITU/Dolby:
Container (5 canaux, folder)
├── Container - L (mono → canal 1)
├── Container - R (mono → canal 2)
├── Container - C (mono → canal 3)
├── Container - LS (mono → canal 4)
└── Container - RS (mono → canal 5)

SMPTE:
Container (5 canaux, folder)
├── Container - L (mono → canal 1)
├── Container - C (mono → canal 2)
├── Container - R (mono → canal 3)
├── Container - LS (mono → canal 4)
└── Container - RS (mono → canal 5)
```

## Code clé corrigé

### Création des tracks multi-channel
```lua
-- Container devient folder
reaper.SetMediaTrackInfo_Value(containerTrack, "I_FOLDERDEPTH", 1)

-- Insertion correcte des enfants
for i = 1, config.channels do
    -- Toujours insérer juste après le container
    reaper.InsertTrackAtIndex(containerIdx + 1, false)
    local channelTrack = reaper.GetTrack(0, containerIdx + i)

    -- Configuration mono
    reaper.SetMediaTrackInfo_Value(channelTrack, "I_NCHAN", 1)

    -- Routing mono vers mono
    local srcChannels = 1024  -- Mode mono
    local dstChannels = 1024 + (routing[i] - 1)  -- Mode mono + canal
```

### Régénération
```lua
-- Détection du mode
local isMultiChannel = container.channelMode and container.channelMode > 0

if isMultiChannel then
    -- Obtenir et nettoyer les tracks enfants
    channelTracks = Generation.getExistingChannelTracks(containerGroup)
    Generation.clearChannelTracks(channelTracks)
else
    -- Nettoyer le container lui-même
    -- Générer directement sur le container
end
```

## Tests à effectuer

1. **Création Quad**: Vérifier que 4 tracks enfants sont créées sous le container
2. **Routing Matrix**: Confirmer L→1, R→2, LS→3, RS→4 dans la matrice de routing
3. **Régénération**: Cliquer "Regenerate" et vérifier que les items sont remplacés sans recréer les tracks
4. **Mode 5.0 SMPTE**: Vérifier que le center est bien en canal 2
5. **Retour au Default**: Vérifier que les tracks enfants sont supprimées et la génération se fait sur le container

## Points d'attention

- Les tracks doivent apparaître indentées sous le container dans l'interface Reaper
- Le routing doit montrer "1→1", "1→2", etc. (mono vers mono) dans la matrice
- La régénération doit préserver la structure existante si "Keep existing tracks" est activé
- Les variantes ITU/SMPTE doivent changer l'ordre des canaux pour 5.0 et 7.0