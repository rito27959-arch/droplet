// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est l'écran « Mode urgence » — pensé pour les situations de
// catastrophe (tremblement de terre, coupure de réseau, etc.) où on veut
// vite dire à TOUT LE MONDE à portée « je vais bien », même sans
// Internet. Un gros bouton rouge « Je suis en sécurité » (qui bat
// doucement, comme un cœur, pour bien attirer l'attention) diffuse ce
// message à tout le mesh — pas seulement à ses contacts habituels,
// littéralement à n'importe quel appareil Droplet à portée. On peut
// choisir d'y ajouter sa position, mais TOUJOURS arrondie (jamais exacte)
// pour rester prudent.
//
// En dessous, la liste de tous les check-in « en sécurité » reçus des
// autres — les plus récents (moins de 2 minutes) sont mis en valeur en
// vert pour bien les distinguer des plus anciens.
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/models/mesh_message.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/storage_service.dart';
import '../../design_system/ouro_alert.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_spinner.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/design_tokens.dart';
import '../../shared/widgets/peer_avatar.dart';
import '../../design_system/liquid_bridge.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/scene_animee.dart';

/// Mode urgence/catastrophe : diffuser un check-in "je suis en sécurité" à
/// tout le mesh, et voir les check-in reçus des autres. Statut public par
/// nature (comme une diffusion mesh totale), pas ciblé à un contact précis.
class SafetyScreen extends ConsumerStatefulWidget {
  const SafetyScreen({super.key});

  @override
  ConsumerState<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends ConsumerState<SafetyScreen> {
  StreamSubscription<SafetyCheckinRecord>? _sub;
  List<SafetyCheckinRecord> _checkins = [];
  bool _sending = false;

  /// Ma propre position, si je l'ai.
  ///
  /// Elle ne sert qu'à SITUER les autres par rapport à moi (« à 420 m au
  /// nord-est ») : sans point de référence, des coordonnées seules ne
  /// veulent rien dire pour un être humain.
  Position? _myPosition;

  @override
  void initState() {
    super.initState();
    _checkins = StorageService.getSafetyCheckins();
    _sub = ref.read(meshRepositoryProvider).safetyCheckinEvents.listen((_) {
      if (mounted) setState(() => _checkins = StorageService.getSafetyCheckins());
    });
    _refreshMyPosition();
  }

  /// Relève ma position en arrière-plan, sans bloquer l'écran ni rien
  /// demander de plus : si la permission n'a jamais été accordée, on
  /// s'en passe et on affiche simplement « position partagée ».
  Future<void> _refreshMyPosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings:
                const LocationSettings(accuracy: LocationAccuracy.low),
          );
      if (mounted) setState(() => _myPosition = position);
    } catch (_) {
      // Pas de position : ce n'est pas une erreur, juste une information
      // en moins.
    }
  }

  /// Traduit une position en langage courant, par rapport à la mienne.
  ///
  /// ⚠️ C'est le remplacement des COORDONNÉES BRUTES qui s'affichaient
  /// ici (« ≈ 3.85, 11.50 »). Une latitude et une longitude ne disent
  /// rien à personne : dans une situation d'urgence, ce qu'on veut
  /// savoir, c'est si la personne est loin, et de quel côté.
  String _describeLocation(SafetyCheckinRecord c) {
    if (!c.hasLocation) return 'Position non partagée';

    final me = _myPosition;
    if (me == null) {
      // Sans point de référence de mon côté, on ne peut rien situer —
      // mais on peut au moins dire que l'information existe.
      return 'Position partagée';
    }

    final metres = Geolocator.distanceBetween(
      me.latitude,
      me.longitude,
      c.lat!,
      c.lon!,
    );
    final bearing = Geolocator.bearingBetween(
      me.latitude,
      me.longitude,
      c.lat!,
      c.lon!,
    );

    return '${_formatDistance(metres)} ${_formatBearing(bearing)}';
  }

  /// « à 420 m », « à 1,2 km », « à 15 km ».
  ///
  /// La précision diminue avec la distance : au-delà du kilomètre,
  /// personne n'a besoin du détail au mètre près, et l'afficher
  /// donnerait une fausse impression d'exactitude — la position
  /// partagée est de toute façon volontairement arrondie.
  String _formatDistance(double metres) {
    if (metres < 950) {
      final rounded = (metres / 10).round() * 10;
      return 'à $rounded m';
    }
    final km = metres / 1000;
    if (km < 10) return 'à ${km.toStringAsFixed(1).replaceAll('.', ',')} km';
    return 'à ${km.round()} km';
  }

  /// « au nord », « au sud-est »… à partir d'un cap en degrés.
  String _formatBearing(double bearing) {
    const points = [
      'au nord',
      'au nord-est',
      "à l'est",
      'au sud-est',
      'au sud',
      'au sud-ouest',
      "à l'ouest",
      'au nord-ouest',
    ];
    // Le cap va de -180 à 180 : on le ramène sur 0-360 avant de le
    // découper en huit secteurs de 45°.
    final normalized = (bearing + 360) % 360;
    final index = ((normalized + 22.5) ~/ 45) % 8;
    return points[index];
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Demande la permission de localisation et récupère une position
  /// approximative — retourne `null` sans faire d'histoires si la
  /// permission est refusée ou le GPS désactivé (la diffusion peut se
  /// faire sans position, ce n'est jamais bloquant).
  Future<Position?> _tryGetApproxLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return null;
      }
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      );
    } catch (_) {
      return null;
    }
  }

  /// Demande d'abord si on veut inclure une position, puis diffuse le
  /// check-in « je suis en sécurité » à tout le mesh.
  Future<void> _sendCheckin() async {
    final includeLocation = await ouroChoice<bool>(
      context,
      title: 'Diffuser « Je suis en sécurité » ?',
      message: 'Ce statut sera visible par tout le mesh à portée, pas '
          'seulement tes contacts. Tu peux inclure une position '
          'approximative (arrondie, jamais exacte).',
      options: const [
        OuroChoiceOption(label: 'Avec position approx.', value: true),
        OuroChoiceOption(label: 'Sans position', value: false),
      ],
    );
    if (includeLocation == null || !mounted) return;

    setState(() => _sending = true);
    try {
      double? lat;
      double? lon;
      if (includeLocation) {
        final position = await _tryGetApproxLocation();
        lat = position?.latitude;
        lon = position?.longitude;
      }
      await ref.read(meshRepositoryProvider).sendSafetyCheckin(lat: lat, lon: lon);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Statut diffusé au mesh', type: DropletToastType.success);
    } catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Échec de la diffusion', type: DropletToastType.error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Demande d'aide — envoie un check-in « j'ai besoin d'aide » au mesh.
  Future<void> _sendHelpRequest() async {
    final includeLocation = await ouroChoice<bool>(
      context,
      title: "Diffuser « J'ai besoin d'aide » ?",
      message: 'Ce statut signalera aux pairs à portée que tu as besoin '
          "d'assistance. Tu peux inclure une position approximative.",
      options: const [
        OuroChoiceOption(label: 'Avec position approx.', value: true),
        OuroChoiceOption(label: 'Sans position', value: false),
      ],
    );
    if (includeLocation == null || !mounted) return;

    setState(() => _sending = true);
    try {
      double? lat;
      double? lon;
      if (includeLocation) {
        final position = await _tryGetApproxLocation();
        lat = position?.latitude;
        lon = position?.longitude;
      }
      await ref.read(meshRepositoryProvider).sendSafetyCheckin(lat: lat, lon: lon);
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      ref.read(toastProvider.notifier).show("Demande d'aide diffusée au mesh", type: DropletToastType.warning);
    } catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Échec de la diffusion', type: DropletToastType.error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'à l\'instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    return 'il y a ${diff.inDays} j';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OuroColors.background,
      appBar: AppBar(
        backgroundColor: OuroColors.background,
        elevation: 0,
        leading: const OuroBackButton(),
        title: Text('Mode urgence',
            style: TextStyle(color: OuroColors.textPrimary, fontWeight: FontWeight.w700)),
        actions: [
          // La carte est l'autre moitié de cet écran : la liste dit QUI
          // est en sécurité, la carte dit OÙ. Un aller-retour direct
          // entre les deux évite de repasser par les réglages.
          Semantics(
            button: true,
            label: 'Voir sur la carte',
            child: IconButton(
              tooltip: 'Voir sur la carte',
              icon: Icon(Icons.map_rounded, color: OuroColors.meshBlueBright),
              onPressed: () => context.push('/map'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(DesignTokens.screenMargin, 8, DesignTokens.screenMargin, DesignTokens.space8),
        children: [
          _SafetyButton(sending: _sending, onTap: _sendCheckin),
          const SizedBox(height: 12),
          // Demande d'aide — bouton secondaire pour signaler
          // un besoin d'assistance (pas juste « je suis en sécurité »).
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _sending ? null : _sendHelpRequest,
              icon: Icon(Icons.priority_high_rounded, color: OuroColors.systemOrange, size: 20),
              label: Text("J'ai besoin d'aide",
                  style: TextStyle(color: OuroColors.systemOrange, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: OuroColors.systemOrange.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusLg)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Check-in reçus (${_checkins.length})',
              style: TextStyle(color: OuroColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (_checkins.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: EmptyState(
                emoji: Scenes.toutVaBien,
                icon: Icons.shield_outlined,
                title: 'Aucun check-in reçu pour le moment',
                subtitle: 'Les statuts « en sécurité » diffusés par les pairs à portée apparaîtront ici.',
                iconColor: OuroColors.textTertiary,
              ),
            )
          else
            ..._checkins.asMap().entries.map((entry) {
              final i = entry.key;
              final c = entry.value;
              final fresh = DateTime.now().difference(c.timestamp).inMinutes < 2;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: fresh ? OuroColors.successGreen.withValues(alpha: 0.08) : OuroColors.glassBg,
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                  border: Border.all(color: fresh ? OuroColors.successGreen.withValues(alpha: 0.4) : OuroColors.glassBorder),
                ),
                child: Row(
                  children: [
                    PeerAvatar(pseudo: c.pseudo, radius: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.pseudo, style: TextStyle(color: OuroColors.textPrimary, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            c.hasLocation
                                ? 'En sécurité · ${_timeAgo(c.timestamp)} · ${_describeLocation(c)}'
                                : 'En sécurité · ${_timeAgo(c.timestamp)}',
                            style: TextStyle(
                              color: fresh ? OuroColors.successGreen : OuroColors.textTertiary,
                              fontSize: 12,
                              fontWeight: fresh ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      label: 'En sécurité',
                      child: LiquidGlassBox(
                        padding: EdgeInsets.zero,
                        child: Icon(Icons.check_circle_rounded, color: OuroColors.successGreen, size: 20),
                      ),
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(delay: (i * 50).ms, duration: DesignTokens.durationNormal)
                  .slideY(begin: 0.15, curve: DesignTokens.curveEmphasis);
            }),
        ],
      ),
    );
  }
}

/// Bouton principal du mode urgence : bouclier qui bat doucement + anneau
/// rouge pulsé — signal volontairement plus marqué qu'un bouton classique,
/// cohérent avec l'enjeu (situation de stress, besoin d'inviter à l'action).
class _SafetyButton extends StatefulWidget {
  const _SafetyButton({required this.sending, required this.onTap});
  final bool sending;
  final VoidCallback onTap;

  @override
  State<_SafetyButton> createState() => _SafetyButtonState();
}

class _SafetyButtonState extends State<_SafetyButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  int _countdown = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    if (_countdown > 0) return;
    setState(() => _countdown = 3);
    HapticFeedback.heavyImpact();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() {
        _countdown--;
        if (_countdown > 0) HapticFeedback.mediumImpact();
      });
      if (_countdown <= 0) {
        timer.cancel();
        widget.onTap();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            boxShadow: DesignTokens.glow(OuroColors.errorRed, radius: 14 + _pulse.value * 14, spread: 1 + _pulse.value * 2),
          ),
          child: child,
        );
      },
      child: Semantics(
        button: true,
        label: 'Diffuser mon statut de sécurité au réseau mesh',
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: widget.sending ? null : _startCountdown,
            style: FilledButton.styleFrom(
              backgroundColor: OuroColors.errorRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusLg)),
            ),
            icon: widget.sending
                ? const SizedBox(
                    width: 20, height: 20,
                    child: OuroSpinner(color: Colors.white, radius: 9),
                  )
                : AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => Transform.scale(
                      scale: 1.0 + _pulse.value * 0.12,
                      child: const Icon(Icons.shield_rounded),
                    ),
                  ),
            label: Text(
              _countdown > 0 ? '$_countdown…' : 'Je suis en sécurité',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}
