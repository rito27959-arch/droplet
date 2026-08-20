// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LA BOÎTE NOIRE DE L'APPLICATION.
//
// Quand Droplet rencontre une erreur qu'aucun `try/catch` n'attrape, ce
// fichier l'écrit dans un petit journal sur l'appareil, avec l'heure, le
// message et la pile d'appels. Rien d'autre : pas d'envoi sur Internet
// (l'app n'a pas de serveur, et ce serait contraire à sa promesse), pas
// de données personnelles, pas de contenu de message.
//
// ── Pourquoi c'était indispensable ────────────────────────────────────
//
// Jusqu'ici, une erreur non attrapée dans Droplet ne laissait
// STRICTEMENT AUCUNE TRACE une fois l'app relancée. En développement,
// on voit l'écran rouge ou la console. Chez l'utilisateur, l'écran
// clignote, l'app se ferme, et il ne reste rien à examiner — on en est
// réduit à deviner. C'est exactement ce qui s'est passé avec le
// plantage de la carte : impossible de savoir, après coup, si c'était
// une exception Dart, un manque de mémoire, ou le pilote graphique.
//
// ── Les deux portes par lesquelles une erreur peut sortir ─────────────
//
// Flutter en a deux, distinctes, et il faut tenir les DEUX :
//
//   • `FlutterError.onError` — les erreurs du framework lui-même :
//     un `build()` qui lève, une contrainte de mise en page impossible,
//     une image qui ne se décode pas.
//   • `PlatformDispatcher.instance.onError` — les erreurs asynchrones
//     qui n'appartiennent à aucun widget : un `Future` non surveillé,
//     un flux qui échoue. Sans ce second crochet, elles disparaissent
//     silencieusement.
//
// ── Ce que ce journal ne peut PAS capturer ────────────────────────────
//
// Il est écrit en Dart, donc il ne survit pas à ce qui tue le processus
// avant lui : une erreur dans du code natif (Kotlin, un pilote
// graphique, SQLite), ou le système qui ferme l'app pour récupérer de
// la mémoire. Ces cas-là ne se lisent que dans `adb logcat`. Le journal
// tranche donc une question utile : si l'app se ferme et que le journal
// est VIDE, la cause n'est pas côté Dart.
// ============================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Le journal des erreurs non attrapées.
class CrashJournal {
  CrashJournal._();

  static File? _fichier;

  /// Au-delà de cette taille, le journal est réduit de moitié.
  ///
  /// Un journal qui grossit sans limite finirait par occuper plus de
  /// place que les messages eux-mêmes. 64 Ko, c'est largement de quoi
  /// tenir plusieurs centaines d'erreurs — et de toute façon, ce sont
  /// les plus RÉCENTES qui servent à diagnostiquer.
  static const int _tailleMax = 64 * 1024;

  /// Branche les deux crochets d'erreur de Flutter.
  ///
  /// À appeler une seule fois, au tout début de `main()`, juste après
  /// `ensureInitialized()` — avant tout code susceptible d'échouer.
  static Future<void> install() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _fichier = File('${dir.path}/droplet-erreurs.log');
    } catch (_) {
      // Sans dossier accessible, on continue quand même : les erreurs
      // seront au moins affichées dans la console.
    }

    final precedent = FlutterError.onError;
    FlutterError.onError = (details) {
      // On garde le comportement d'origine (écran rouge en développement,
      // trace en console) EN PLUS de l'enregistrement : le journal
      // complète le diagnostic, il ne le remplace pas.
      precedent?.call(details);
      _ecrire(
        'FLUTTER',
        details.exceptionAsString(),
        details.stack,
        contexte: details.context?.toDescription(),
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      _ecrire('ASYNC', error.toString(), stack);
      // `true` = « c'est traité ». On le dit pour que l'app continue de
      // tourner : une tuile de carte qui échoue ne doit pas emporter une
      // conversation en cours.
      return true;
    };
  }

  /// Ajoute une ligne au journal, sans jamais faire échouer l'appelant.
  static void _ecrire(String source, String message, StackTrace? pile,
      {String? contexte}) {
    debugPrint('[Journal/$source] $message');
    final fichier = _fichier;
    if (fichier == null) return;
    // `unawaited` : on n'attend PAS l'écriture disque. Le crochet
    // d'erreur peut être appelé en plein milieu d'une image ; le faire
    // attendre le disque ferait sauter cette image.
    unawaited(_ajouter(fichier, source, message, pile, contexte));
  }

  static Future<void> _ajouter(File fichier, String source, String message,
      StackTrace? pile, String? contexte) async {
    try {
      final horodatage = DateTime.now().toIso8601String();
      final tampon = StringBuffer()
        ..writeln('── $horodatage · $source ──────────────');
      if (contexte != null) tampon.writeln('Contexte : $contexte');
      tampon.writeln(message);
      if (pile != null) {
        // Dix niveaux d'appels suffisent à situer l'origine ; une pile
        // complète peut faire cent lignes et noie le journal.
        final lignes = pile.toString().split('\n');
        tampon.writeln(lignes.take(10).join('\n'));
      }
      tampon.writeln();

      await fichier.writeAsString(tampon.toString(),
          mode: FileMode.append, flush: false);

      if (await fichier.length() > _tailleMax) await _reduire(fichier);
    } catch (_) {
      // Un journal qui plante en enregistrant un plantage serait la pire
      // des ironies. On abandonne silencieusement.
    }
  }

  /// Ne garde que la seconde moitié du journal.
  static Future<void> _reduire(File fichier) async {
    try {
      final contenu = await fichier.readAsString();
      await fichier.writeAsString(contenu.substring(contenu.length ~/ 2));
    } catch (_) {}
  }

  /// Le contenu du journal, pour l'afficher ou le partager depuis les
  /// paramètres. `null` si aucune erreur n'a jamais été enregistrée.
  static Future<String?> lire() async {
    final fichier = _fichier;
    if (fichier == null || !await fichier.exists()) return null;
    try {
      final contenu = await fichier.readAsString();
      return contenu.trim().isEmpty ? null : contenu;
    } catch (_) {
      return null;
    }
  }

  /// Vide le journal.
  static Future<void> vider() async {
    try {
      await _fichier?.writeAsString('');
    } catch (_) {}
  }
}
