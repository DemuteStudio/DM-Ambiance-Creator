# Guide de Test des Zones de Waveform

## ⚠️ IMPORTANT: Testez dans cet ordre

## Problèmes Corrigés
✅ Erreur `relative_x nil` lors du Ctrl+Click
✅ Création de zones avec Shift+Click ne fonctionnait pas
✅ Réorganisation du code pour gérer les interactions dans le bon ordre

## Tests à effectuer

### 1. Création de zone
- **Shift + Clic gauche + Drag** : Maintenez Shift, cliquez et faites glisser pour créer une zone
- La zone doit apparaître en vert transparent pendant la création
- Une fois relâché, la zone devient bleue quasi-transparente

### 2. Déplacement de zone
- Cliquez à l'intérieur d'une zone (pas sur les bords)
- Le curseur doit changer en main
- Faites glisser pour déplacer la zone

### 3. Redimensionnement
- Passez le curseur sur le bord gauche ou droit d'une zone
- Le curseur doit changer en flèche de redimensionnement
- Cliquez et faites glisser pour redimensionner

### 4. Suppression
- **Ctrl + Clic** sur une zone pour la supprimer directement
- **Clic droit** sur une zone pour ouvrir le menu contextuel avec option de suppression

### 5. Menu contextuel (Clic droit)
- Renommer la zone
- Jouer l'audio de la zone
- Supprimer la zone
- Effacer toutes les zones

### 6. Vérifier l'isolation
- Les interactions avec les zones ne doivent PAS déclencher la lecture audio
- Seuls les clics dans l'espace vide doivent déclencher la lecture

### 7. Vérifier la persistance
- Créez des zones sur un item
- Sélectionnez un autre item
- Revenez au premier item - les zones doivent être toujours là

## Ordre des Interactions (Priorité)
1. Ctrl+Click (suppression)
2. Shift+Click (création)
3. Double-click (reset position)
4. Click simple (lecture/position)
5. Clic droit (menu contextuel)

## En cas de problème
Si une fonctionnalité ne marche pas, vérifiez :
- Que vous maintenez bien les touches modificatrices (Shift, Ctrl)
- Que vous cliquez dans la zone de la waveform (pas en dehors)
- Que vous n'avez pas d'autre interaction en cours (drag, resize, etc.)