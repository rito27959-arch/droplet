// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LE WIDGET QUI DONNE VIE AUX ÉCRANS VIDES, AUX ATTENTES ET AUX RÉUSSITES.
//
// Partout dans Droplet, il y avait la même chose : une grosse icône grise
// immobile, un titre, une phrase. C'est correct, et c'est mort. Les
// applications qu'on cite en exemple mettent, à cet endroit précis, une
// petite scène animée — pas pour décorer, mais parce qu'un écran vide est
// un moment où l'utilisateur se demande s'il a fait une erreur. Un
// mouvement doux répond « non, c'est normal, il n'y a juste rien encore ».
//
// ── ⚠️ POURQUOI LOTTIE ET PAS RIVE ────────────────────────────────────
//
// La question s'est posée sérieusement, et la réponse est une question de
// LICENCE, pas de technique.
//
// Rive est excellent — plus léger, interactif, avec de vraies machines à
// états. Mais il n'existe PAS de lot d'animations `.riv` réutilisables :
// le dépôt officiel `rive-app/animations`, seul lot publié sous licence
// MIT, contient exactement UN fichier. Le reste vit sur la galerie
// communautaire de Rive, où chaque fichier porte ses propres conditions,
// souvent restrictives. Embarquer ça dans une application publiée serait
// prendre un risque juridique pour de la décoration.
//
// Les emojis animés de Noto, eux, sont publiés par Google sous CC BY 4.0 :
// usage commercial autorisé, redistribution autorisée, à la seule
// condition de créditer — ce que fait l'écran « À propos ». Ce sont de
// vraies animations vectorielles Lottie, les mêmes que dans les
// applications de Google.
//
// ── Le repli n'est pas un détail ──────────────────────────────────────
//
// Chaque scène garde son icône d'origine en secours. Si l'animation
// manque — asset non déclaré, fichier abîmé, mémoire insuffisante — on
// retombe sur exactement ce qu'il y avait avant. Un écran vide qui
// devient un écran CASSÉ serait un très mauvais échange.
// ============================================================================

import 'package:animated_emoji/animated_emoji.dart';
import 'package:flutter/material.dart';

import '../../design_system/ouro_colors.dart';

/// Une animation Noto, désignée par son nom de fichier.
///
/// Les noms viennent du paquet `animated_emoji` et doivent figurer dans
/// la liste des assets de `pubspec.yaml` — sinon l'animation ne charge
/// pas et le repli prend le relais.
class SceneAnimee extends StatelessWidget {
  const SceneAnimee({
    super.key,
    required this.emoji,
    required this.iconeDeSecours,
    this.taille = 88,
    this.repete = true,
  });

  /// L'animation à jouer.
  final AnimatedEmojiData emoji;

  /// Ce qu'on affiche si l'animation ne se charge pas.
  final IconData iconeDeSecours;

  final double taille;

  /// En boucle pour une attente ou un état vide ; une seule fois pour une
  /// réussite, où la répétition finirait par agacer.
  final bool repete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: taille,
      width: taille,
      child: AnimatedEmoji(
        emoji,
        size: taille,
        repeat: repete,
        // ⚠️ `asset` EST OBLIGATOIRE ICI.
        //
        // Par défaut, le paquet va chercher l'animation sur
        // `fonts.gstatic.com`. Dans Droplet — une application qui
        // fonctionne SANS INTERNET, c'est sa raison d'être — ce serait
        // absurde : la scène ne s'afficherait jamais là où elle sert le
        // plus, c'est-à-dire hors connexion.
        source: AnimatedEmojiSource.asset,
        errorWidget: Icon(
          iconeDeSecours,
          size: taille * 0.6,
          color: OuroColors.systemGray3,
        ),
      ),
    );
  }
}

/// Le répertoire des scènes de l'application.
///
/// ⚠️ Une seule table, volontairement. Le risque d'un projet où chaque
/// écran choisit son animation dans son coin, c'est trente animations qui
/// n'ont aucun rapport les unes avec les autres — l'effet « sapin de
/// Noël » plutôt que l'effet « application vivante ». Les avoir toutes
/// sous les yeux, ici, permet de vérifier d'un coup d'œil que l'ensemble
/// se tient.
///
/// ⚠️ Chaque nom utilisé ici DOIT figurer dans les assets déclarés par
/// `pubspec.yaml`. Sinon, c'est le repli qui s'affiche — silencieusement.
class Scenes {
  Scenes._();

  // ── Conversations ─────────────────────────────────────────────────
  static const aucuneConversation = AnimatedEmojis.wave;
  static const aucunResultat = AnimatedEmojis.eyes;
  static const conversationVide = AnimatedEmojis.smile;
  static const diffusionVide = AnimatedEmojis.rocket;

  // ── Pairs et réseau ───────────────────────────────────────────────
  static const aucunPair = AnimatedEmojis.thinkingFace;
  static const rechercheDePairs = AnimatedEmojis.eyes;
  static const pairTrouve = AnimatedEmojis.handshake;
  static const reseauActif = AnimatedEmojis.electricity;

  // ── Appels ────────────────────────────────────────────────────────
  static const aucunAppel = AnimatedEmojis.sleep;
  static const appelEnCours = AnimatedEmojis.electricity;
  static const appelManque = AnimatedEmojis.cry;

  // ── Statuts et actualités ─────────────────────────────────────────
  static const aucunStatut = AnimatedEmojis.ghost;
  static const aucuneActualite = AnimatedEmojis.yawn;

  // ── Groupes ───────────────────────────────────────────────────────
  static const aucunGroupe = AnimatedEmojis.foldedHands;
  static const groupeCree = AnimatedEmojis.partyPopper;

  // ── Cartes ────────────────────────────────────────────────────────
  static const aucuneCarte = AnimatedEmojis.rainbow;
  static const positionIntrouvable = AnimatedEmojis.thinkingFace;

  // ── Sécurité et sauvegarde ────────────────────────────────────────
  static const sauvegardeReussie = AnimatedEmojis.checkMark;
  static const alerte = AnimatedEmojis.warning;
  static const urgence = AnimatedEmojis.fire;
  static const toutVaBien = AnimatedEmojis.relieved;
  static const identiteVerifiee = AnimatedEmojis.starStruck;

  // ── Contribution ──────────────────────────────────────────────────
  static const contribution = AnimatedEmojis.muscle;
  static const felicitations = AnimatedEmojis.confettiBall;

  // ── Partage et fichiers ───────────────────────────────────────────
  static const partage = AnimatedEmojis.balloon;
  static const envoiReussi = AnimatedEmojis.thumbsUp;
  static const echecEnvoi = AnimatedEmojis.crossMark;

  // ── Divers ────────────────────────────────────────────────────────
  static const chargement = AnimatedEmojis.glowingStar;
  static const erreur = AnimatedEmojis.melting;
  static const bienvenue = AnimatedEmojis.wave;
}
