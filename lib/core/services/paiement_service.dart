// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LE PAIEMENT MOBILE MONEY : demander, attendre, recevoir la licence.
//
// ── ⚠️ CE QUE CE FICHIER NE FAIT PAS, ET C'EST L'ESSENTIEL ────────────
//
// Il ne décide JAMAIS que quelque chose est débloqué. Il ne fait que
// rapporter une licence signée, que `PremiumService` vérifiera comme
// toutes les autres — avec le même code, la même clé publique, les mêmes
// refus.
//
// Cette séparation est ce qui rend le réseau inoffensif. Quelqu'un qui
// détourne la connexion, remplace le serveur ou fabrique une fausse
// réponse obtient au mieux une chaîne de caractères que la vérification
// de signature rejette. Il n'existe aucun chemin où « le serveur a dit
// oui » suffise.
//
// ── ⚠️ ET POURQUOI LE MESH N'EST PAS CONCERNÉ ─────────────────────────
//
// C'est le seul endroit de Droplet qui contacte quoi que ce soit sur
// internet, et il ne sert qu'à encaisser. Aucun message, aucun contact,
// aucune clé de conversation n'y passe — jamais. Sans réseau, ce fichier
// échoue proprement et l'application continue exactement comme avant :
// la saisie manuelle d'une licence reste disponible, et la messagerie
// n'a jamais eu besoin de rien de tout ça.
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// L'adresse du délivreur de licences.
///
/// ⚠️ VIDE = PAIEMENT AUTOMATIQUE DÉSACTIVÉ, et c'est un état normal,
/// pas une panne. Tant que le Worker n'est pas déployé, l'écran n'affiche
/// que la marche à suivre manuelle — ce qui vaut mieux qu'un bouton
/// « Payer » qui échoue.
const String kServeurLicences = '';

/// Où en est une demande de paiement.
enum EtatPaiement {
  /// La demande est partie, la personne doit taper son code sur son
  /// téléphone.
  attente,

  /// Payé et licence reçue.
  reussi,

  /// Refusé, annulé, ou solde insuffisant.
  echec,

  /// Le serveur est injoignable, ou n'est pas configuré.
  indisponible,
}

class ResultatPaiement {
  const ResultatPaiement(this.etat, {this.licence, this.message});

  final EtatPaiement etat;

  /// La licence signée, présente uniquement si [etat] vaut
  /// [EtatPaiement.reussi].
  final String? licence;

  final String? message;
}

class PaiementService {
  PaiementService._();

  static bool get disponible => kServeurLicences.isNotEmpty;

  /// Combien de temps on attend que la personne tape son code.
  ///
  /// Trois minutes : le temps de sortir le téléphone, lire l'invite, se
  /// souvenir de son code secret et le taper. En deçà, on abandonne des
  /// paiements qui allaient aboutir — et l'argent, lui, sera bien parti.
  static const Duration _attenteMax = Duration(minutes: 3);

  /// L'intervalle entre deux vérifications.
  ///
  /// Trois secondes : assez court pour que le déblocage paraisse
  /// immédiat, assez long pour ne pas marteler le serveur pendant trois
  /// minutes.
  static const Duration _intervalle = Duration(seconds: 3);

  static const Duration _delaiReseau = Duration(seconds: 20);

  /// Lance l'encaissement. La personne reçoit une invite sur son
  /// téléphone.
  ///
  /// Renvoie la référence de la transaction, ou `null` si la demande n'a
  /// pas pu partir.
  static Future<String?> demander({
    required String codeAppareil,
    required String offre,
    required String telephone,
  }) async {
    if (!disponible) return null;
    try {
      final rep = await http
          .post(
            Uri.parse('$kServeurLicences/payer'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'appareil': codeAppareil,
              'offre': offre,
              'telephone': telephone,
            }),
          )
          .timeout(_delaiReseau);
      if (rep.statusCode != 200) {
        debugPrint('[Paiement] refus ${rep.statusCode}: ${rep.body}');
        return null;
      }
      final data = jsonDecode(rep.body) as Map<String, dynamic>;
      return data['reference'] as String?;
    } catch (e) {
      debugPrint('[Paiement] demande impossible: $e');
      return null;
    }
  }

  /// Attend que le paiement aboutisse, puis renvoie la licence.
  ///
  /// ⚠️ UN ÉCHEC RÉSEAU NE VAUT PAS UN ÉCHEC DE PAIEMENT, et confondre
  /// les deux serait grave : l'argent peut très bien être parti pendant
  /// que la connexion tombait. Une coupure passagère est donc réessayée
  /// jusqu'à la fin du délai, et l'on ne conclut à l'échec que lorsque
  /// le serveur le dit explicitement.
  static Future<ResultatPaiement> attendre(
    String reference, {
    void Function()? surBattement,
  }) async {
    if (!disponible) {
      return const ResultatPaiement(EtatPaiement.indisponible);
    }
    final fin = DateTime.now().add(_attenteMax);

    while (DateTime.now().isBefore(fin)) {
      await Future<void>.delayed(_intervalle);
      surBattement?.call();
      try {
        final rep = await http
            .get(Uri.parse('$kServeurLicences/licence?reference=$reference'))
            .timeout(_delaiReseau);
        if (rep.statusCode != 200) continue;

        final data = jsonDecode(rep.body) as Map<String, dynamic>;
        switch (data['etat']) {
          case 'ok':
            final licence = data['licence'] as String?;
            if (licence == null || licence.isEmpty) continue;
            return ResultatPaiement(EtatPaiement.reussi, licence: licence);
          case 'echec':
            return const ResultatPaiement(
              EtatPaiement.echec,
              message: 'Le paiement n\'est pas allé au bout.',
            );
          default:
            // « attente » : la personne n'a pas encore validé.
            continue;
        }
      } catch (e) {
        // Coupure passagère : on retente au prochain tour.
        debugPrint('[Paiement] vérification manquée: $e');
      }
    }

    return const ResultatPaiement(
      EtatPaiement.attente,
      message: 'Toujours sans confirmation. Si l\'argent a été débité, '
          'votre licence reste récupérable — écrivez-nous.',
    );
  }
}
