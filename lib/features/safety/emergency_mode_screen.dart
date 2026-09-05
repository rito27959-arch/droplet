import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/mesh_provider.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_spinner.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/design_tokens.dart';

class EmergencyModeScreen extends ConsumerStatefulWidget {
  const EmergencyModeScreen({super.key});

  @override
  ConsumerState<EmergencyModeScreen> createState() => _EmergencyModeScreenState();
}

class _EmergencyModeScreenState extends ConsumerState<EmergencyModeScreen>
    with SingleTickerProviderStateMixin {
  bool _sosActive = false;
  bool _broadcasting = false;

  /// Les ondes qui partent du bouton quand le SOS est actif.
  ///
  /// ── Pourquoi des ondes et pas le halo qui était là ────────────────
  ///
  /// Le bouton portait une ombre rouge floue de quarante points. Elle
  /// avait deux défauts, et le second est le vrai.
  ///
  /// D'abord, c'est un halo coloré, l'effet que `design_tokens.dart`
  /// bannit dans toute l'application.
  ///
  /// Surtout, un halo est IMMOBILE. Sur un écran de détresse, la seule
  /// question qui compte est « est-ce que ça émet, là, maintenant ? » —
  /// et une lueur figée ne répond pas : elle ressemble exactement à une
  /// décoration. Des ondes qui partent en boucle du bouton disent qu'un
  /// signal est réellement en train d'être diffusé, et se lisent d'un
  /// bout à l'autre d'une pièce, y compris pour quelqu'un qui ne
  /// regarde pas l'écran de face.
  ///
  /// C'est le vocabulaire qu'emploie iOS pour ce qui émet : le point de
  /// localisation qui cherche un signal, AirDrop, la recherche
  /// d'accessoires.
  late final AnimationController _ondes;

  @override
  void initState() {
    super.initState();
    _ondes = AnimationController(
      vsync: this,
      // Deux secondes et demie : le rythme d'un appel au secours, pas
      // celui d'un chargement. Plus rapide, cela devient nerveux ; plus
      // lent, on ne voit plus le mouvement.
      duration: const Duration(milliseconds: 2500),
    );
  }

  @override
  void dispose() {
    _ondes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OuroColors.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: _sosActive
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    OuroColors.errorRed.withValues(alpha: 0.15),
                    OuroColors.background,
                    OuroColors.background,
                  ],
                )
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    // Un voile rouge très dilué en haut d'écran plutôt
                    // qu'un bleu nuit fixe : il porte le sens de l'écran, et
                    // il fonctionne aussi bien sur fond blanc que noir.
                    Color.alphaBlend(
                      OuroColors.systemRed.withValues(alpha: 0.10),
                      OuroColors.systemBackground,
                    ),
                    OuroColors.systemBackground,
                    OuroColors.systemBackground,
                  ],
                ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    const OuroBackButton(),
                    Expanded(
                      child: Text('Mode urgence',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: OuroColors.textPrimary)),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Centre — gros bouton SOS
              Column(
                children: [
                  GestureDetector(
                    onTap: _toggleSos,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                    // Les ondes, DERRIÈRE le bouton.
                    if (_sosActive)
                      AnimatedBuilder(
                        animation: _ondes,
                        builder: (context, _) => SizedBox(
                          width: 300,
                          height: 300,
                          child: CustomPaint(
                            painter: _OndesSos(
                              avancement: _ondes.value,
                              couleur: OuroColors.errorRed,
                              rayonDepart: 90,
                            ),
                          ),
                        ),
                      ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      width: _sosActive ? 180 : 160,
                      height: _sosActive ? 180 : 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: _sosActive
                              ? [OuroColors.errorRed, Color(0xFFFF1744)]
                              : [OuroColors.errorRed.withValues(alpha: 0.3), OuroColors.errorRed.withValues(alpha: 0.15)],
                        ),
                        // Le halo est parti dans les ondes, au-dessus.
                        boxShadow:
                            _sosActive ? DesignTokens.floatingShadow : const [],
                        border: Border.all(
                          color: _sosActive ? OuroColors.errorRed : OuroColors.errorRed.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _sosActive ? Icons.warning_rounded : Icons.sos_rounded,
                            color: Colors.white,
                            size: _sosActive ? 48 : 42,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _sosActive ? 'SOS ACTIF' : 'SOS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: _sosActive ? 18 : 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    _sosActive
                        // ⚠️ CETTE LIGNE ÉTAIT À MOITIÉ EN CHINOIS :
                        // « Signal SOS actif —扩散到所有附近设备 ».
                        //
                        // Du texte non traduit, affiché à l'utilisateur,
                        // sur l'écran d'urgence — celui qu'on lit dans
                        // les pires conditions possibles. C'est le seul
                        // endroit de l'application où cela se produisait.
                        ? 'Signal SOS actif — diffusé à tous les appareils '
                            'à portée'
                        : 'Tirez pour envoyer un signal d\'urgence',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _sosActive ? OuroColors.errorRed : OuroColors.textSecondary,
                      fontSize: 15,
                      fontWeight: _sosActive ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Le signal est relayé de pair en pair\nsur tout le réseau mesh.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: OuroColors.textTertiary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Actions en bas
              Padding(
                padding: const EdgeInsets.fromLTRB(DesignTokens.screenMargin, 0, DesignTokens.screenMargin, DesignTokens.space8),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _broadcasting ? null : _broadcastCheckIn,
                        icon: _broadcasting
                            ? const SizedBox(width: 18, height: 18, child: OuroSpinner(color: Colors.white, radius: 9))
                            : const Icon(Icons.check_circle_rounded, size: 20),
                        label: Text(
                          _broadcasting ? 'Diffusion...' : 'Je suis en sécurité',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: OuroColors.successGreen,
                          side: BorderSide(color: OuroColors.successGreen, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.location_on_rounded, size: 20),
                        label: const Text(
                          'Partager ma position',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: OuroColors.meshBlueBright,
                          side: BorderSide(color: OuroColors.meshBlueBright, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleSos() {
    HapticFeedback.heavyImpact();
    setState(() => _sosActive = !_sosActive);
    if (_sosActive) {
      // ⚠️ Les ondes ne tournent QUE pendant le SOS. Un `repeat()` laissé
      // en marche est un ticker qui réveille l'application soixante fois
      // par seconde pour rien — sur un écran d'urgence, où la batterie
      // est précisément ce qui peut manquer, c'est le dernier endroit où
      // se le permettre.
      _ondes.repeat();
      ref.read(toastProvider.notifier).show('Signal SOS activé', type: DropletToastType.warning);
    } else {
      _ondes.stop();
      _ondes.value = 0;
    }
  }

  Future<void> _broadcastCheckIn() async {
    HapticFeedback.mediumImpact();
    setState(() => _broadcasting = true);
    try {
      await ref.read(meshRepositoryProvider).sendStatus('🟢 Je suis en sécurité');
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Statut de sécurité diffusé', type: DropletToastType.success);
    } catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Échec de la diffusion', type: DropletToastType.error);
    } finally {
      if (mounted) setState(() => _broadcasting = false);
    }
  }
}

/// Les ondes du signal SOS : deux anneaux qui partent du bouton et
/// s'effacent en s'éloignant.
///
/// ── Pourquoi deux, et décalés ─────────────────────────────────────────
///
/// Un seul anneau donne un battement — un éclair toutes les deux
/// secondes et demie, avec un long vide entre deux. Deux anneaux décalés
/// d'un demi-cycle donnent une ÉMISSION CONTINUE : il y a toujours
/// quelque chose en train de partir. C'est la différence entre « ça
/// clignote » et « ça émet », et c'est exactement ce que fait iOS pour
/// tout ce qui cherche ou diffuse un signal.
class _OndesSos extends CustomPainter {
  _OndesSos({
    required this.avancement,
    required this.couleur,
    required this.rayonDepart,
  });

  /// 0 → 1, en boucle.
  final double avancement;
  final Color couleur;

  /// Le rayon du bouton : les ondes partent de son bord, pas de son
  /// centre — sans quoi on les voit naître à l'intérieur du disque.
  final double rayonDepart;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final rayonMax = size.width / 2;

    for (var i = 0; i < 2; i++) {
      // Le second anneau est à un demi-cycle du premier.
      final t = (avancement + i * 0.5) % 1.0;

      // L'onde ralentit en s'éloignant (racine du temps) : une onde qui
      // avance à vitesse constante paraît mécanique, alors qu'une onde
      // réelle perd de la vitesse en se diluant.
      final progression = math.sqrt(t);
      final rayon = rayonDepart + (rayonMax - rayonDepart) * progression;

      // Elle s'efface en s'éloignant, et le trait s'affine : c'est ce
      // qui fait qu'on la lit comme une onde et non comme un cercle.
      final opacite = (1 - t) * 0.55;
      if (opacite <= 0.01) continue;

      canvas.drawCircle(
        centre,
        rayon,
        Paint()
          ..color = couleur.withValues(alpha: opacite)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * (1 - t) + 0.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OndesSos old) =>
      old.avancement != avancement ||
      old.couleur != couleur ||
      old.rayonDepart != rayonDepart;
}
