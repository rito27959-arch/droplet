// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'AFFICHAGE d'un message vocal : le dessin de la voix (les petites
// barres verticales) et la bulle complète qui l'entoure — lecture,
// déplacement dans l'enregistrement, vitesse, et le bouton micro qui
// permet de répondre à une voix par la voix.
//
// La durée et la forme d'onde elles-mêmes viennent de
// `core/models/voice_note_meta.dart` : ce fichier-ci ne sait que les
// dessiner.
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models/voice_note_meta.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';
import '../../design_system/ouro_haptics.dart';

// ─────────────────────────────────────────────────────────────
//  LE DESSIN DE LA VOIX
// ─────────────────────────────────────────────────────────────

/// Les barres verticales qui représentent la voix, avec la partie déjà
/// écoutée colorée et le reste en gris — et le doigt peut se poser
/// dessus pour se déplacer dans l'enregistrement.
class VoiceWaveform extends StatelessWidget {
  const VoiceWaveform({
    super.key,
    required this.waveform,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    this.onSeek,
    this.height = 30,
  });

  final List<double> waveform;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  /// Appelé quand on pose ou glisse le doigt sur l'onde, avec la
  /// position visée entre 0 et 1.
  final ValueChanged<double>? onSeek;

  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        void seek(Offset local) {
          final w = constraints.maxWidth;
          if (w <= 0 || onSeek == null) return;
          onSeek!((local.dx / w).clamp(0.0, 1.0));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: onSeek == null
              ? null
              : (d) {
                  OuroHaptics.selection();
                  seek(d.localPosition);
                },
          onHorizontalDragUpdate:
              onSeek == null ? null : (d) => seek(d.localPosition),
          child: SizedBox(
            height: height,
            child: CustomPaint(
              painter: _VoiceWaveformPainter(
                waveform: waveform.isEmpty
                    ? _fallback
                    : waveform,
                progress: progress,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
              ),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }

  /// Dessin neutre pour les vocaux reçus d'une version de Droplet qui ne
  /// transmettait pas encore la forme d'onde. Volontairement PLAT et
  /// régulier : inventer un relief donnerait l'illusion d'une
  /// information qu'on n'a pas.
  static final List<double> _fallback =
      List<double>.filled(VoiceNoteMeta.bars, 0.32);
}

class _VoiceWaveformPainter extends CustomPainter {
  _VoiceWaveformPainter({
    required this.waveform,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  final List<double> waveform;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  static const double _barWidth = 2.5;
  static const double _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty || size.width <= 0) return;

    // ⚠️ On ne dessine PAS systématiquement les 48 valeurs reçues : à 130
    // points de large, elles se chevaucheraient et l'onde deviendrait un
    // pavé plein, sans relief lisible. On calcule donc combien de barres
    // tiennent réellement, et on résume le relevé à ce nombre-là en
    // gardant le PIC de chaque tranche — c'est le pic qui porte la forme
    // de la voix, une moyenne l'aplatirait.
    final slot = _barWidth + _gap;
    final count = math.max(1, math.min(waveform.length, (size.width / slot).floor()));
    final bars = _condense(waveform, count);

    final radius = const Radius.circular(_barWidth / 2);
    final played = progress.clamp(0.0, 1.0) * count;
    final mid = size.height / 2;
    // Centré : quand le relevé ne remplit pas toute la largeur, l'onde ne
    // doit pas se coller au bord gauche.
    final startX = (size.width - (count * slot - _gap)) / 2;

    for (var i = 0; i < count; i++) {
      // Une barre garde toujours une hauteur minimale : à zéro elle
      // disparaîtrait, et l'onde semblerait trouée.
      final h = (2.5 + bars[i] * (size.height - 3)).clamp(2.5, size.height);
      final x = startX + i * slot;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, mid - h / 2, _barWidth, h),
        radius,
      );

      // La barre à cheval sur la tête de lecture est peinte en deux
      // temps, sinon la progression avancerait par saccades d'une barre
      // entière au lieu de glisser.
      if (i + 1 <= played) {
        canvas.drawRRect(rect, Paint()..color = activeColor);
      } else if (i < played) {
        canvas.drawRRect(rect, Paint()..color = inactiveColor);
        canvas.save();
        canvas.clipRect(
            Rect.fromLTWH(x, 0, _barWidth * (played - i), size.height));
        canvas.drawRRect(rect, Paint()..color = activeColor);
        canvas.restore();
      } else {
        canvas.drawRRect(rect, Paint()..color = inactiveColor);
      }
    }
  }

  /// Résume [input] à [target] valeurs en gardant le maximum de chaque
  /// tranche.
  static List<double> _condense(List<double> input, int target) {
    if (input.length <= target) return input;
    final out = <double>[];
    for (var i = 0; i < target; i++) {
      final start = (i * input.length / target).floor();
      final end = math.max(start + 1, ((i + 1) * input.length / target).ceil());
      var peak = 0.0;
      for (var j = start; j < end && j < input.length; j++) {
        if (input[j] > peak) peak = input[j];
      }
      out.add(peak);
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter old) =>
      old.progress != progress ||
      old.activeColor != activeColor ||
      old.inactiveColor != inactiveColor ||
      !identical(old.waveform, waveform);
}

// ─────────────────────────────────────────────────────────────
//  LA BULLE D'UN MESSAGE VOCAL
// ─────────────────────────────────────────────────────────────

/// Le contenu d'une bulle de message vocal : lecture, forme d'onde,
/// durée, vitesse de lecture, et — sur les vocaux reçus — le bouton
/// micro qui permet de répondre à la voix par la voix.
class VoiceNoteBubble extends StatelessWidget {
  const VoiceNoteBubble({
    super.key,
    required this.meta,
    this.fileSize,
    required this.mine,
    required this.playing,
    required this.progress,
    required this.position,
    required this.speed,
    required this.played,
    required this.onPlayPause,
    required this.onSeek,
    required this.onCycleSpeed,
    this.onVoiceReply,
  });

  /// Durée et forme d'onde. `null` pour un vocal reçu d'une version
  /// antérieure de Droplet, ou pour un fichier audio simplement joint.
  final VoiceNoteMeta? meta;

  /// Poids du fichier, en octets — sert UNIQUEMENT de repli quand [meta]
  /// est absent.
  final int? fileSize;

  final bool mine;
  final bool playing;

  /// Avancement de la lecture, 0..1.
  final double progress;

  /// Position de lecture, pour l'affichage du temps.
  final Duration? position;

  /// Vitesse en cours (1.0, 1.5 ou 2.0).
  final double speed;

  /// Vrai si ce vocal a déjà été écouté au moins une fois.
  final bool played;

  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeek;
  final VoidCallback onCycleSpeed;

  /// Répondre par un vocal — proposé uniquement sur les messages reçus.
  final VoidCallback? onVoiceReply;

  @override
  Widget build(BuildContext context) {
    // Sur une bulle bleue (mes messages), tout est blanc. Sur une bulle
    // grise (messages reçus), tout suit la couleur du texte du mode en
    // cours — c'est ce qui manquait avant : les commandes étaient peintes
    // en blanc dans les deux cas, donc invisibles sur fond gris clair.
    final onBubble = mine ? Colors.white : OuroColors.label;
    final accent = mine ? Colors.white : OuroColors.accent;
    final dim = onBubble.withValues(alpha: 0.45);

    // La durée mesurée si on l'a ; sinon une estimation d'après le poids
    // du fichier. C'est l'ancienne méthode, approximative — mais un
    // « 0:04 » à peu près juste se lit infiniment mieux qu'un « —:— »
    // qui donne l'impression que le message est cassé.
    final total = meta?.duration ?? _estimateFromSize(fileSize);

    // Pendant la lecture on décompte le temps restant, comme toutes les
    // messageries : c'est l'information qu'on cherche à ce moment-là.
    final label = playing && total != null && position != null
        ? _fmt(total - position!)
        : total != null
            ? _fmt(total)
            : '—:—';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Lecture / pause ────────────────────────────────────────
        _CircleButton(
          icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
          onTap: onPlayPause,
          background: mine
              ? Colors.white.withValues(alpha: 0.22)
              : OuroColors.accent,
          foreground: mine ? Colors.white : Colors.white,
          size: 36,
          iconSize: 22,
        ),
        const SizedBox(width: 10),

        // ── Onde + durée ───────────────────────────────────────────
        SizedBox(
          width: 132,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VoiceWaveform(
                waveform: meta?.waveform ?? const [],
                progress: progress,
                activeColor: accent,
                inactiveColor: onBubble.withValues(alpha: 0.3),
                onSeek: onSeek,
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Text(
                    label,
                    style: OuroTypography.caption1.copyWith(color: dim),
                  ),
                  // La pastille bleue des vocaux jamais écoutés — la
                  // convention est immédiatement comprise, et c'est la
                  // seule façon de repérer d'un coup d'œil ce qui reste
                  // à écouter dans une longue conversation.
                  if (!mine && !played) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: OuroColors.accent,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),

        // ── Vitesse de lecture ─────────────────────────────────────
        // N'apparaît qu'une fois la lecture lancée : un réglage de
        // vitesse sur un message à l'arrêt n'a rien à dire.
        if (playing) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              OuroHaptics.selection();
              onCycleSpeed();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: onBubble.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                speed == 1.0 ? '1×' : '${speed.toString().replaceAll('.', ',')}×',
                style: OuroTypography.caption2.copyWith(
                  color: onBubble,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],

        // ── Répondre par la voix ───────────────────────────────────
        // Le raccourci demandé : on vient d'écouter quelqu'un, on
        // répond en parlant sans repasser par le champ de texte ni
        // viser le bouton micro tout en bas de l'écran.
        if (onVoiceReply != null) ...[
          const SizedBox(width: 6),
          _CircleButton(
            icon: Icons.mic_rounded,
            onTap: () {
              HapticFeedback.mediumImpact();
              onVoiceReply!();
            },
            background: OuroColors.accent.withValues(alpha: 0.16),
            foreground: OuroColors.accent,
            size: 30,
            iconSize: 17,
            tooltip: 'Répondre par un vocal',
          ),
        ],
      ],
    );
  }

  /// Estimation grossière : l'encodage AAC utilisé tourne autour de
  /// 32 ko par seconde de parole.
  static Duration? _estimateFromSize(int? bytes) {
    if (bytes == null || bytes <= 0) return null;
    return Duration(seconds: (bytes / 32000).round().clamp(1, 3599));
  }

  static String _fmt(Duration d) {
    final sec = d.inSeconds.clamp(0, 3599);
    return '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
  }
}

/// Petit bouton rond avec assombrissement au doigt (jamais d'onde
/// Material, comme partout ailleurs dans l'app).
class _CircleButton extends StatefulWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    required this.background,
    required this.foreground,
    required this.size,
    required this.iconSize,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color background;
  final Color foreground;
  final double size;
  final double iconSize;
  final String? tooltip;

  @override
  State<_CircleButton> createState() => _CircleButtonState();
}

class _CircleButtonState extends State<_CircleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    Widget button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.background,
          ),
          child: Icon(
            widget.icon,
            color: widget.foreground,
            size: widget.iconSize,
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}
