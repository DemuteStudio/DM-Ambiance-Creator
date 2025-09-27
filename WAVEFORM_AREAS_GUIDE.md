# Guide des Zones de Waveform

## Nouvelles Commandes

### Création de Zones
- **Shift + Clic gauche + Drag** : Créer une nouvelle zone
  - Maintenez Shift, cliquez avec le bouton gauche et faites glisser pour définir la zone

### Manipulation des Zones
- **Clic gauche sur zone** : Déplacer la zone
  - Cliquez dans une zone (pas sur les bords) et faites glisser pour la déplacer

- **Clic gauche sur bord** : Redimensionner
  - Cliquez sur le bord gauche ou droit d'une zone pour la redimensionner
  - Le curseur change en flèche de redimensionnement au survol

- **Ctrl + Clic gauche** : Supprimer rapidement une zone
  - Maintenez Ctrl et cliquez sur une zone pour la supprimer

### Menu Contextuel
- **Clic droit sur zone** : Ouvrir le menu contextuel
  - Renommer la zone
  - Jouer l'audio de la zone
  - Supprimer la zone
  - Effacer toutes les zones

## Points Importants

### Zones uniques par item
- Les zones sont maintenant sauvegardées par item, pas par fichier
- Chaque item a ses propres zones même s'ils utilisent le même fichier audio
- Les zones sont conservées lors du changement d'item sélectionné

### Interaction avec la lecture
- Les interactions avec les zones (création, déplacement, redimensionnement) ne déclenchent plus la lecture audio
- Seuls les clics en dehors des zones déclenchent la lecture

## Raccourcis Récapitulatifs
- **Shift + Clic gauche + Drag** : Créer zone
- **Clic gauche sur zone** : Déplacer
- **Clic gauche sur bord** : Redimensionner
- **Clic droit sur zone** : Menu
- **Ctrl + Clic** : Supprimer
- **Clic simple (hors zone)** : Définir position de lecture
- **Double-clic (hors zone)** : Réinitialiser position

## Style Visuel
- Zones quasi-transparentes (5% d'opacité)
- Poignées de redimensionnement subtiles
- Mise en surbrillance au survol
- Labels affichés si l'espace le permet