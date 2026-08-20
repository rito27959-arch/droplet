# Stickers animés

Ce dossier est **volontairement vide**. Déposez-y vos animations et elles
apparaîtront automatiquement dans le panneau de stickers de la
conversation — aucune ligne de code à écrire.

## Formats acceptés

| Extension | Ce que c'est |
|---|---|
| `.tgs` | Le format de Telegram : un JSON Lottie compressé en gzip |
| `.json` | Une animation Lottie non compressée |

## Où les ranger

```
assets/stickers/
├── fetes/
│   ├── confettis.tgs
│   └── gateau.tgs
└── humeurs/
    ├── content.tgs
    └── fatigue.json
```

Le nom du **sous-dossier** devient le nom du lot dans le panneau. Un
fichier posé directement à la racine tombe dans un lot nommé
« stickers ».

⚠️ Après avoir ajouté ou retiré des fichiers, relancez complètement
l'application (`flutter run`), pas seulement un rechargement à chaud :
l'index des assets est construit à la compilation.

## ⚠️ Droits d'usage

**N'y déposez pas les stickers de Telegram.** Ils appartiennent à
Telegram ou à leurs auteurs ; les embarquer dans une application publiée
serait une contrefaçon, et suffirait à faire refuser Droplet sur les
magasins d'applications.

Sources d'animations libres :

- **[LottieFiles](https://lottiefiles.com/free-animations)** — beaucoup
  d'animations sous licence libre. Vérifiez la licence de CHAQUE fichier,
  elle varie d'un auteur à l'autre.
- **Vos propres animations**, exportées d'After Effects avec le greffon
  Bodymovin, ou dessinées dans un éditeur Lottie.

## Contraintes techniques

Ce ne sont pas des recommandations de style, ce sont les limites qui
font qu'un sticker reste utilisable sur un téléphone modeste :

- **512 × 512** au maximum ;
- **3 secondes** au plus, en boucle ;
- **60 images par seconde** ;
- idéalement **sous 50 ko** — au-delà, le décodage devient perceptible à
  l'ouverture du panneau, où plusieurs stickers tournent en même temps.

## Comment ça circule sur le mesh

Ce qui est envoyé n'est **pas le fichier** : c'est une référence de
quelques dizaines d'octets, du type `🎞tgs:fetes/confettis`. Chaque
appareil affiche l'animation depuis ses propres fichiers.

C'est indispensable ici : en Bluetooth, Droplet ne dispose que de
**dix-neuf octets utiles par écriture**. Envoyer un sticker de 30 ko
demanderait plus de mille cinq cents écritures — pendant lesquelles les
vrais messages attendraient derrière.

**Conséquence à connaître :** un correspondant qui n'a pas le même lot de
stickers ne verra pas l'animation. Il verra le nom du sticker et une
mention expliquant qu'il lui manque le fichier. Pour que les stickers
s'affichent des deux côtés, les deux appareils doivent avoir la même
version de l'application.
