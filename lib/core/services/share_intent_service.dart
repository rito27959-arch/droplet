// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Sur Android, quand on regarde une photo dans une autre app et qu'on
// appuie sur « Partager », un menu apparaît avec la liste des apps
// capables de recevoir ce partage (WhatsApp, Gmail, etc.). Ce fichier,
// c'est ce qui permet à DROPLET d'apparaître dans ce menu, et de savoir
// « attraper » ce qui vient d'être partagé (texte, photo, fichier...)
// pour ensuite proposer à l'utilisateur de choisir à QUI, dans Droplet,
// il veut l'envoyer.
//
// Le contenu partagé n'est jamais sauvegardé directement — il reste dans
// une petite « salle d'attente » en mémoire ([pendingItems]) jusqu'à ce
// que l'utilisateur ait choisi le destinataire sur l'écran
// `ShareTargetScreen`. Un peu comme un colis qui reste sur le comptoir
// de la poste tant que personne n'a indiqué l'adresse de livraison.
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

/// Relie les intents de partage Android (« Partager vers… » → Droplet) à la
/// navigation de l'app. Le contenu partagé transite par [pendingItems], un
/// état transitoire en mémoire — jamais persisté avant qu'un destinataire
/// soit choisi dans [ShareTargetScreen].
class ShareIntentService {
  ShareIntentService._();

  static bool _initialized = false;

  /// Ce qui a été partagé vers Droplet et attend qu'on choisisse un
  /// destinataire — vide tant que rien n'a été partagé.
  static List<SharedMediaFile> pendingItems = const [];

  /// À appeler une fois au démarrage : se met à l'écoute de deux cas
  /// différents — un partage qui arrive alors que Droplet tourne déjà
  /// (le flux `getMediaStream`), et un partage qui a servi à OUVRIR
  /// Droplet depuis fermé (`getInitialMedia`, lu une seule fois au tout
  /// début).
  static Future<void> init({required void Function() onShared}) async {
    if (_initialized) return;
    _initialized = true;

    // Écouté pour toute la durée de vie du processus, jamais annulé — au
    // même titre que les autres services singletons de l'app (mesh, etc.).
    ReceiveSharingIntent.instance.getMediaStream().listen((items) {
      if (items.isEmpty) return;
      pendingItems = items;
      onShared();
    }, onError: (e) => debugPrint('[ShareIntentService] flux invalide: $e'));

    try {
      final initial = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initial.isNotEmpty) {
        pendingItems = initial;
        ReceiveSharingIntent.instance.reset();
        onShared();
      }
    } catch (e) {
      debugPrint('[ShareIntentService] échec lecture intent initial: $e');
    }
  }

  /// Vide la salle d'attente — une fois que l'utilisateur a choisi un
  /// destinataire (ou annulé), il n'y a plus rien à garder en mémoire.
  static void clear() {
    pendingItems = const [];
  }
}
