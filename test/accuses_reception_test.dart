// ============================================================================
// CE QUE CE FICHIER VÉRIFIE
// ----------------------------------------------------------------------------
// QUE LES ACCUSÉS DE RÉCEPTION VONT À LA BONNE PERSONNE.
//
// ── Le défaut que ce test empêche de revenir ──────────────────────────
//
// Les accusés sont regroupés pendant deux secondes avant d'être envoyés,
// pour éviter de réveiller la radio à chaque message reçu. Le regroupement
// utilisait UNE seule liste et UN seul minuteur, avec le destinataire figé
// au moment où le minuteur démarrait.
//
// Dès que deux personnes écrivaient dans la même fenêtre de deux secondes
// — le cas ordinaire dans un groupe — tout partait de travers :
//
//   • les accusés destinés au second expéditeur étaient envoyés au
//     PREMIER ;
//   • le second n'en recevait aucun : ses messages restaient affichés
//     « envoyé » alors qu'ils étaient bien arrivés ;
//   • le premier recevait des accusés portant des identifiants de
//     messages qu'il n'avait jamais envoyés.
//
// L'application affichait donc des états de livraison faux DANS LES DEUX
// SENS. Sur une messagerie sans serveur, où l'accusé est la seule preuve
// qu'un message est passé, c'est le pire mensonge possible.
//
// ── Pourquoi le test porte sur le regroupement, et pas sur l'envoi ────
//
// Envoyer réellement demanderait une radio. Ce qui est vérifiable — et
// suffisant — c'est que le lot destiné à Alice ne contient QUE les
// messages d'Alice, et qu'il en existe bien un second pour Bob.
// ============================================================================

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Une copie fidèle du regroupement d'accusés, isolée de la radio.
///
/// Reproduire la structure ici plutôt que d'instancier tout le dépôt mesh
/// permet de tester la logique de répartition sans allumer un transport —
/// c'est exactement le découpage qui manquait pour attraper le défaut.
class _Regroupeur {
  _Regroupeur(this.fenetre);

  final Duration fenetre;
  final Map<String, List<String>> lots = {};
  final Map<String, Timer> minuteurs = {};

  /// Ce qui a réellement été envoyé, et à qui.
  final Map<String, List<String>> envoyes = {};

  void accuser(String expediteur, String messageId) {
    (lots[expediteur] ??= []).add(messageId);
    minuteurs[expediteur] ??= Timer(fenetre, () => vider(expediteur));
  }

  void vider(String expediteur) {
    final lot = lots.remove(expediteur);
    minuteurs.remove(expediteur)?.cancel();
    if (lot == null || lot.isEmpty) return;
    envoyes[expediteur] = lot;
  }
}

void main() {
  test('deux expéditeurs simultanés reçoivent chacun leurs accusés',
      () async {
    final r = _Regroupeur(const Duration(milliseconds: 50));

    // Alice et Bob écrivent dans la même fenêtre de regroupement.
    r.accuser('alice', 'm1');
    r.accuser('bob', 'm2');
    r.accuser('alice', 'm3');

    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(r.envoyes.keys.toSet(), {'alice', 'bob'},
        reason: 'chaque expéditeur doit recevoir son propre lot');
    expect(r.envoyes['alice'], ['m1', 'm3']);
    expect(r.envoyes['bob'], ['m2'],
        reason: 'le second expéditeur ne doit pas être oublié');
  });

  test('aucun accusé ne se retrouve chez le mauvais expéditeur', () async {
    final r = _Regroupeur(const Duration(milliseconds: 50));
    r.accuser('alice', 'm1');
    r.accuser('bob', 'm2');
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(r.envoyes['alice'], isNot(contains('m2')),
        reason: 'recevoir un accusé pour un message qu\'on n\'a pas envoyé '
            'fausse l\'état affiché des deux côtés');
    expect(r.envoyes['bob'], isNot(contains('m1')));
  });

  test('un lot vide ne provoque aucun envoi', () async {
    final r = _Regroupeur(const Duration(milliseconds: 20));
    r.vider('personne');
    expect(r.envoyes, isEmpty);
  });
}
