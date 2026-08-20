// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// La carte d'identité d'un MESSAGE VOCAL : sa durée réelle et le dessin
// de la voix (la « forme d'onde »), plus la façon dont ces deux
// informations voyagent d'un téléphone à l'autre.
//
// ── Le problème que ce fichier résout ──────────────────────────────────
//
// Avant, un message vocal affichait :
//   • une DURÉE DEVINÉE à partir du poids du fichier (poids ÷ 32000).
//     Un enregistrement fait dans le silence pèse beaucoup moins lourd
//     qu'un enregistrement fait dans le bruit, à durée identique — la
//     durée affichée était donc souvent fausse de plusieurs secondes.
//   • une FORME D'ONDE INVENTÉE : dix-huit barres dont les hauteurs
//     étaient écrites en dur dans le code. Tous les messages vocaux de
//     l'app, de tout le monde, avaient exactement le même dessin.
//
// Désormais la durée est mesurée pendant l'enregistrement, et la forme
// d'onde est le vrai relevé du volume de la voix. On voit donc
// réellement où la personne a parlé fort, où elle a marqué une pause.
//
// ── Comment ça voyage jusqu'à l'autre téléphone ? ──────────────────────
//
// C'est la partie astucieuse. Ces informations sont rangées DANS LE NOM
// DU FICHIER : au lieu de s'appeler `voix.m4a`, l'enregistrement
// s'appelle par exemple `voix~3f~8KPfRc....m4a`. Le nom du fichier fait
// déjà le voyage jusqu'à l'autre téléphone, chiffré avec le reste — il
// n'y a donc RIEN à changer au format des paquets réseau, et un
// téléphone équipé d'une version antérieure de Droplet reçoit simplement
// un fichier au nom un peu bizarre, sans que rien ne casse.
//
// (L'affichage, lui, vit dans `features/chat/voice_note.dart` : ce
// fichier-ci ne connaît rien aux couleurs ni aux widgets, ce qui permet
// à la liste des conversations de s'en servir aussi.)
// ============================================================================

import 'dart:math' as math;

/// Durée réelle et forme d'onde réelle d'un message vocal.
class VoiceNoteMeta {
  const VoiceNoteMeta({required this.duration, required this.waveform});

  /// Durée mesurée à l'enregistrement.
  final Duration duration;

  /// Le volume de la voix au fil du temps, entre 0 et 1, en [bars]
  /// valeurs. Vide si l'enregistrement vient d'une version de Droplet
  /// qui ne la transmettait pas encore.
  final List<double> waveform;

  /// Nombre de barres dessinées. 48 est un compromis : assez pour que le
  /// relief de la voix se lise, assez peu pour que le nom de fichier
  /// reste court (48 caractères).
  static const int bars = 48;

  static const String _prefix = 'voix';

  /// Un caractère = une barre. Ces 64 caractères sont tous acceptés dans
  /// un nom de fichier sur Android comme sur iOS ; c'est pour ça qu'on
  /// évite `/`, `+` ou les espaces.
  static const String _alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_';

  /// Fabrique le nom de fichier qui transportera ces informations.
  ///
  /// [samples] peut contenir n'importe quel nombre de relevés : ils sont
  /// ramenés à [bars] barres en faisant la moyenne de chaque tranche.
  static String encodeFileName({
    required Duration duration,
    required List<double> samples,
  }) {
    final envelope = _resample(samples, bars);
    final buffer = StringBuffer();
    for (final v in envelope) {
      final index = (v.clamp(0.0, 1.0) * 63).round();
      buffer.write(_alphabet[index]);
    }
    final ms = duration.inMilliseconds.clamp(0, 1 << 30);
    return '$_prefix~${ms.toRadixString(36)}~$buffer.m4a';
  }

  /// Relit ces informations depuis un nom de fichier.
  ///
  /// Renvoie `null` si le nom ne suit pas la convention — c'est le cas
  /// des vocaux reçus d'une version antérieure de l'app, et de tous les
  /// autres fichiers audio (une musique partagée, par exemple).
  static VoiceNoteMeta? tryParse(String? fileName) {
    if (fileName == null) return null;
    if (!fileName.startsWith('$_prefix~')) return null;

    final withoutExt = fileName.endsWith('.m4a')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;
    final parts = withoutExt.split('~');
    if (parts.length != 3) return null;

    final ms = int.tryParse(parts[1], radix: 36);
    if (ms == null) return null;

    final envelope = <double>[];
    for (final c in parts[2].split('')) {
      final index = _alphabet.indexOf(c);
      // Un seul caractère inattendu et on renonce à la forme d'onde :
      // mieux vaut retomber sur l'affichage neutre que dessiner un
      // relief faux à partir de données abîmées.
      if (index < 0) return null;
      envelope.add(index / 63);
    }

    return VoiceNoteMeta(
      duration: Duration(milliseconds: ms),
      waveform: envelope,
    );
  }

  /// Vrai si ce nom de fichier désigne un message vocal enregistré dans
  /// Droplet (par opposition à un fichier audio joint).
  static bool isVoiceNote(String? fileName) =>
      fileName != null &&
      (fileName.startsWith('$_prefix~') || fileName == 'voix.m4a');

  /// Comment nommer une pièce jointe dans un aperçu (citation, réponse,
  /// liste des médias).
  ///
  /// Sans cette fonction, un vocal cité s'affichait avec son nom de
  /// fichier brut — `voix~3f~8KPfRc....m4a` — ce qui ressemble à un bug
  /// alors que c'est justement là que se cachent la durée et l'onde.
  static String describeAttachment(String? fileName) {
    if (!isVoiceNote(fileName)) return fileName ?? '📎 Fichier';
    final meta = tryParse(fileName);
    if (meta == null) return '🎤 Message vocal';
    final sec = meta.duration.inSeconds;
    return '🎤 Message vocal · '
        '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
  }

  /// Ramène une liste de relevés de longueur quelconque à exactement
  /// [target] valeurs, en moyennant chaque tranche.
  ///
  /// Une simple prise « une valeur sur N » perdrait les pics : dans un
  /// enregistrement, ce sont précisément les pics qui donnent au dessin
  /// sa ressemblance avec la voix.
  static List<double> _resample(List<double> input, int target) {
    if (input.isEmpty) return List<double>.filled(target, 0.15);
    if (input.length == target) return input;

    final out = <double>[];
    for (var i = 0; i < target; i++) {
      final start = (i * input.length / target).floor();
      final end = math.max(start + 1, ((i + 1) * input.length / target).ceil());
      var sum = 0.0;
      var count = 0;
      for (var j = start; j < end && j < input.length; j++) {
        sum += input[j];
        count++;
      }
      out.add(count == 0 ? 0.15 : sum / count);
    }
    return out;
  }

  /// Convertit le niveau sonore brut du micro en une hauteur de barre.
  ///
  /// ⚠️ Le micro ne renvoie PAS une valeur entre 0 et 1 : il renvoie des
  /// décibels pleine échelle (dBFS), c'est-à-dire un nombre NÉGATIF
  /// (0 = saturation, −160 = silence absolu). L'ancien code faisait un
  /// `clamp(0, 1)` là-dessus, ce qui ramenait absolument tout à zéro :
  /// la forme d'onde affichée pendant l'enregistrement était plate et ne
  /// réagissait jamais à la voix.
  static double normalizeDb(double db) {
    if (!db.isFinite) return 0.0;
    // Le plancher de référence : en dessous de −45 dB, on est dans le
    // bruit de fond d'une pièce calme, rien d'intéressant à montrer.
    const floor = -45.0;
    final clamped = db.clamp(floor, 0.0);
    final linear = (clamped - floor) / -floor; // 0 au plancher, 1 à fond
    // Une voix normale se situe assez bas dans l'échelle des décibels ;
    // sans cette courbe, toutes les barres resteraient minuscules.
    return math.pow(linear, 0.62).toDouble();
  }
}
