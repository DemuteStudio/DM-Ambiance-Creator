# Multi-Channel Support - Corrections Finales

## Problèmes corrigés

### 1. ✅ Structure des tracks
**Problème**: Les tracks n'étaient pas enfants du container
**Solution**:
- En mode Default (stereo), génération directe sur le container
- En modes multi-channel, le container devient folder avec tracks enfants

### 2. ✅ Routing mono corrigé
**Problème**: Chaque track envoyait en stéréo au lieu de mono
**Solution**:
- Tracks enfants configurées en mono (1 canal)
- Routing: L→1, R→2, LS→3, RS→4 (pour Quad)
- Parent configuré avec le bon nombre de canaux (4 pour Quad, 5 pour 5.0, 7 pour 7.0)

### 3. ✅ Suppression du LFE
**Problème**: Formats 5.1 et 7.1 incluaient le LFE non utilisé
**Solution**:
- Remplacé par 5.0 et 7.0
- Suppression de FIVE_ONE et SEVEN_ONE

### 4. ✅ Support des normes ITU/SMPTE
**Nouveau**: Support des variantes pour 5.0 et 7.0
- **ITU/Dolby**: L, R, C, LS, RS (standard)
- **SMPTE**: L, C, R, LS, RS (center en position 2)
- Dropdown "Channel Order" ajouté dans l'UI

## Configuration des canaux

### Mode Default (Stereo)
- Génération sur le container lui-même
- 2 canaux
- Pas de tracks enfants

### Mode 4.0 Quad
```
Container (4 canaux)
├── Container - L  (mono → canal 1)
├── Container - R  (mono → canal 2)
├── Container - LS (mono → canal 3)
└── Container - RS (mono → canal 4)
```

### Mode 5.0
```
ITU/Dolby:
Container (5 canaux)
├── Container - L  (mono → canal 1)
├── Container - R  (mono → canal 2)
├── Container - C  (mono → canal 3)
├── Container - LS (mono → canal 4)
└── Container - RS (mono → canal 5)

SMPTE:
Container (5 canaux)
├── Container - L  (mono → canal 1)
├── Container - C  (mono → canal 2)
├── Container - R  (mono → canal 3)
├── Container - LS (mono → canal 4)
└── Container - RS (mono → canal 5)
```

### Mode 7.0
```
ITU/Dolby:
Container (7 canaux)
├── Container - L  (mono → canal 1)
├── Container - R  (mono → canal 2)
├── Container - C  (mono → canal 3)
├── Container - LS (mono → canal 4)
├── Container - RS (mono → canal 5)
├── Container - LB (mono → canal 6)
└── Container - RB (mono → canal 7)

SMPTE:
Container (7 canaux)
├── Container - L  (mono → canal 1)
├── Container - C  (mono → canal 2)
├── Container - R  (mono → canal 3)
├── Container - LS (mono → canal 4)
├── Container - RS (mono → canal 5)
├── Container - LB (mono → canal 6)
└── Container - RB (mono → canal 7)
```

## Interface utilisateur

1. **Channel Mode**: Dropdown pour sélectionner Default, 4.0, 5.0, ou 7.0
2. **Channel Order**: Dropdown pour ITU/Dolby ou SMPTE (visible seulement pour 5.0 et 7.0)
3. **Channel Settings**: Pan et Volume individuels pour chaque canal

## Génération

- **Mode Default**: Items générés directement sur le container
- **Modes multi-channel**: Items générés sur les tracks enfants
- Chaque track enfant génère ses propres items avec les mêmes paramètres de trigger
- Randomisation indépendante par track

## Fichiers modifiés

1. **DM_Ambiance_Constants.lua**
   - Nouveaux CHANNEL_CONFIGS avec variants
   - Suppression de FIVE_ONE et SEVEN_ONE
   - Ajout de totalChannels et hasVariants

2. **DM_Ambiance_Structures.lua**
   - Ajout de channelVariant (0=ITU/Dolby, 1=SMPTE)

3. **DM_Ambiance_UI_Container.lua**
   - Dropdown Channel Order pour les variantes
   - Utilisation des labels selon la variante active

4. **DM_Ambiance_Utils.lua**
   - Utilisation de totalChannels pour le nombre de canaux du parent

5. **DM_Ambiance_Generation.lua**
   - createMultiChannelTracks utilise les variantes
   - Tracks enfants en mono avec routing mono
   - Mode Default génère sur le container

## Tests recommandés

1. Créer un container en mode 4.0 Quad
2. Vérifier que le container a 4 canaux et 4 tracks enfants
3. Vérifier le routing: L→1, R→2, LS→3, RS→4
4. Tester 5.0 avec ITU et SMPTE
5. Vérifier que le center est en position 3 (ITU) ou 2 (SMPTE)
6. Tester la régénération avec "Keep existing tracks"
7. Vérifier que le mode Default génère sur le container sans tracks enfants