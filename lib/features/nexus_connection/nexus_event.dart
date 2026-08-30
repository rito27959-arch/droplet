// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Le vocabulaire des événements Nexus — le langage commun entre les deux
// appareils qui établissent un lien. Chaque événement porte une seed
// partagée qui garantit que les DEUX écrans vivent la même scène visuelle,
// même si leurs horloges et leurs GPU sont différents.
//
// Le protocole est simple : un appareil émet un `NexusEvent`, l'autre le
// reçoit, et les deux lancent simultanément la même animation en utilisant
// la même seed comme source d'aléatoire. Pas de frame-perfect sync (c'est
// impossible sans clk partagé), mais une synchronisation perceptuelle :
// les mêmes formes, les mêmes couleurs, la même intensité, au même
// moment approximatif.
// ============================================================================

import 'dart:math';

/// Phases de la séquence Nexus, dans l'ordre chronologique.
///
/// Chaque phase correspond à un moment visuel distinct. Le contrôleur
/// avance automatiquement d'une phase à la suivante selon les durées
/// définies dans `NexusController`.
enum NexusPhase {
  /// Rien. L'écran est normal, le mesh recherche des pairs.
  idle,

  /// Phase 1 — Éveil : le fond s'assombrit, des particules microscopiques
  /// apparaissent. « Quelque chose arrive. »
  awakening,

  /// Phase 2 — Naissance : une goutte de lumière cristalline naît au
  /// centre de l'écran.
  dropletBirth,

  /// Phase 3 — Connexion : la goutte explose en une onde organique qui
  /// traverse tout l'écran.
  connectionWave,

  /// Phase 4 — Synchronisation : les deux appareils synchronisent leurs
  /// écrans en une seule animation séparée.
  dualSync,

  /// Phase 5 — Identité : la goutte se stabilise, le réseau mesh
  /// apparaît à l'intérieur, les informations s'affichent.
  identity,

  /// Terminé. L'animation se dissout doucement, l'overlay disparaît.
  complete,
}

/// Événement échangé entre les deux appareils pour synchroniser
/// l'animation Nexus.
///
/// Utilisé comme payload dans un `MeshMessage` de type
/// `MeshMessageType.nexus` (à ajouter au protocole).
class NexusEvent {
  const NexusEvent({
    required this.seed,
    required this.timestamp,
    this.intensity = 1.0,
    this.colorSignature = 0xFF0A84FF,
  });

  /// Seed aléatoire partagée : c'est ELLE qui détermine l'univers
  /// visuel. Deux appareils avec la même seed produisent exactement
  /// la même animation, même sur des GPU différents.
  final String seed;

  /// Horloge d'émission (ISO 8601), pour que les deux appareils
  /// puissent estimer le décalage temporel et ajuster leur timing.
  final String timestamp;

  /// Intensité de l'animation (0 à 1). Permet d'adapter l'effet
  /// selon la batterie ou les performances.
  final double intensity;

  /// Signature couleur dérivée du hash du peer ID : chaque paire
  /// d'appareils a une teinte légèrement différente, comme une
  /// empreinte lumineuse unique.
  final int colorSignature;

  /// Génère une seed aléatoire pour une connexion Nexus.
  static String generateSeed() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Dérive une signature couleur à partir de deux peer IDs.
  ///
  /// L'ordre n'importe pas : la combinaison est symétrique, ce qui
  /// garantit que les DEUX appareils affichent la même teinte.
  static int deriveColorSignature(String peerIdA, String peerIdB) {
    final ordered = [peerIdA, peerIdB]..sort();
    final combined = ordered.join(':');
    var hash = 0;
    for (var i = 0; i < combined.length; i++) {
      hash = ((hash << 5) - hash + combined.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    // Teinte dans la plage bleu-violet-cyan — toujours dans la
    // palette « lumineuse » de Droplet, jamais rouge ou orange.
    final hue = 180 + (hash % 80); // 180-260 : cyan → violet
    return _hslToArgb(hue / 360, 0.7, 0.55);
  }

  static int _hslToArgb(double h, double s, double l) {
    final c = (1 - (2 * l - 1).abs()) * s;
    final x = c * (1 - ((h * 6) % 2 - 1).abs());
    final m = l - c / 2;
    double r, g, b;
    final sector = (h * 6).floor() % 6;
    switch (sector) {
      case 0:
        r = c;
        g = x;
        b = 0;
        break;
      case 1:
        r = x;
        g = c;
        b = 0;
        break;
      case 2:
        r = 0;
        g = c;
        b = x;
        break;
      case 3:
        r = 0;
        g = x;
        b = c;
        break;
      case 4:
        r = x;
        g = 0;
        b = c;
        break;
      default:
        r = c;
        g = 0;
        b = x;
        break;
    }
    return (0xFF << 24) |
        (((r + m) * 255).round() << 16) |
        (((g + m) * 255).round() << 8) |
        ((b + m) * 255).round();
  }

  /// Sérialise en JSON pour le protocole mesh.
  Map<String, dynamic> toJson() => {
        'event': 'nexus_connection',
        'seed': seed,
        'timestamp': timestamp,
        'intensity': intensity,
        'color_signature': '0x${colorSignature.toRadixString(16)}',
      };

  /// Désérialise depuis un JSON reçu du réseau.
  factory NexusEvent.fromJson(Map<String, dynamic> json) {
    return NexusEvent(
      seed: json['seed'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      intensity: (json['intensity'] as num?)?.toDouble() ?? 1.0,
      colorSignature: _parseColor(json['color_signature']),
    );
  }

  static int _parseColor(dynamic value) {
    if (value is int) return value;
    if (value is String) {
      return int.parse(value.replaceFirst('0x', ''), radix: 16);
    }
    return 0xFF0A84FF;
  }
}
