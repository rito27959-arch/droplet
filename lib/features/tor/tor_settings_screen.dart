// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Écran de paramètres Tor de Droplet — avec animations et UX soignée.
// ============================================================================

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/tor_service.dart';
import '../../core/providers/tor_providers.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';
import '../../design_system/ouro_list.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_padlock.dart';

class TorSettingsScreen extends ConsumerStatefulWidget {
  const TorSettingsScreen({super.key});

  @override
  ConsumerState<TorSettingsScreen> createState() => _TorSettingsScreenState();
}

class _TorSettingsScreenState extends ConsumerState<TorSettingsScreen>
    with TickerProviderStateMixin {
  late AnimationController _heroController;
  late AnimationController _shieldController;
  late Animation<double> _heroFade;
  late Animation<double> _shieldScale;
  late Animation<double> _shieldGlow;
  bool _generatingAddress = false;

  @override
  void initState() {
    super.initState();

    _heroController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _heroFade = CurvedAnimation(
      parent: _heroController,
      curve: Curves.easeOut,
    );
    _heroController.forward();

    _shieldController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _shieldScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      // ⚠️ C'ÉTAIT `Curves.elasticOut` : le bouclier dépassait sa taille
      // puis revenait, pendant une seconde et demie. Un écran de sécurité
      // est le dernier endroit où l'interface doit avoir l'air de jouer.
      CurvedAnimation(parent: _shieldController, curve: DesignTokens.curveEnter),
    );
    _shieldGlow = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _shieldController, curve: Curves.easeInOut),
    );
    _shieldController.forward();
  }

  @override
  void dispose() {
    _heroController.dispose();
    _shieldController.dispose();
    super.dispose();
  }

  Future<void> _toggleTor(bool enabled) async {
    setState(() => _generatingAddress = true);

    try {
      // ⚠️ PASSER PAR LE NOTIFIER, PAS PAR LE SERVICE.
      //
      // L'appel direct à `torService.start()` allumait bien Tor — mais
      // n'enregistrait rien. Au lancement suivant, tout était éteint, sans
      // que rien ne l'explique : l'utilisateur avait pourtant activé
      // l'interrupteur et l'avait vu passer au vert. Le notifier retient
      // le choix et le rejoue au démarrage.
      await ref.read(torActifProvider.notifier).definir(enabled);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur Tor: $e'),
            backgroundColor: OuroColors.systemRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingAddress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final torState = ref.watch(torStateProvider);
    final isConnected = torState.valueOrNull == TorServiceState.connected;
    final isConnecting = torState.valueOrNull == TorServiceState.connecting;

    return OuroLargeTitleScaffold(
      title: 'Tor',
      backgroundColor: OuroColors.systemGroupedBackground,
      leading: const OuroBackButton(),
      slivers: [
        SliverToBoxAdapter(
          child: FadeTransition(
            opacity: _heroFade,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DesignTokens.screenMargin),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: DesignTokens.space4),

                  // ── Hero animé ──────────────────────────────────────
                  _TorHeroCard(
                    isConnected: isConnected,
                    isConnecting: isConnecting,
                    voulu: ref.watch(torActifProvider),
                    shieldScale: _shieldScale,
                    shieldGlow: _shieldGlow,
                    onToggle: _toggleTor,
                    generatingAddress: _generatingAddress,
                  ),

                  const SizedBox(height: DesignTokens.space5),

                  // ── Section état ────────────────────────────────────
                  OuroListSection(
                    header: 'État',
                    children: [
                      _AnimatedStateRow(
                        state: torState.valueOrNull,
                      ),
                    ],
                  ),

                  const SizedBox(height: DesignTokens.space5),

                  // ── Section contacts ────────────────────────────────
                  if (isConnected) ...[
                    OuroListSection(
                      header: 'Contacts Tor',
                      footer: 'Scannez le QR code d\'un contact pour vous '
                          'connecter via Tor, même à l\'autre bout du monde.',
                      children: [
                        OuroListRow(
                          icon: Icons.qr_code_scanner_rounded,
                          iconColor: OuroColors.accent,
                          title: 'Scanner un QR Code',
                          subtitle: 'Ajouter un contact distant',
                          onTap: () => context.push('/tor/scan'),
                        ),
                        OuroListRow(
                          icon: Icons.qr_code_2_rounded,
                          iconColor: OuroColors.accent,
                          title: 'Mon QR Code',
                          subtitle: 'Partager mon adresse onion',
                          onTap: () => context.push('/tor/qr'),
                        ),
                      ],
                    ),
                    const SizedBox(height: DesignTokens.space5),
                  ],

                  // ── Section avancé ──────────────────────────────────
                  OuroListSection(
                    header: 'Avancé',
                    children: [
                      OuroListRow(
                        icon: Icons.info_outline_rounded,
                        iconColor: OuroColors.systemGray,
                        title: 'Comment ça marche ?',
                        onTap: () => _showHowItWorks(context),
                      ),
                    ],
                  ),

                  const SizedBox(height: DesignTokens.space8),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showHowItWorks(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _HowItWorksSheet(),
    );
  }
}

// ============================================================================
// HERO CARD
// ============================================================================

class _TorHeroCard extends StatelessWidget {
  const _TorHeroCard({
    required this.isConnected,
    required this.isConnecting,
    required this.shieldScale,
    required this.shieldGlow,
    required this.onToggle,
    required this.generatingAddress,
    required this.voulu,
  });

  final bool isConnected;
  final bool isConnecting;
  final Animation<double> shieldScale;
  final Animation<double> shieldGlow;
  final Future<void> Function(bool) onToggle;
  final bool generatingAddress;

  /// Ce que l'utilisateur a DEMANDÉ, indépendamment de ce que le réseau a
  /// réussi à faire.
  ///
  /// ⚠️ L'interrupteur suivait `isConnected || isConnecting`, c'est-à-dire
  /// l'état du circuit. Quand la connexion échouait — réseau qui bloque
  /// Tor, avion, tunnel — l'interrupteur revenait tout seul sur « éteint »
  /// quelques secondes après avoir été activé. L'utilisateur en conclut
  /// que son geste n'a pas été pris en compte, alors que le réglage, lui,
  /// est bien enregistré. Un interrupteur dit une INTENTION ; c'est la
  /// ligne d'état, en dessous, qui dit le résultat.
  final bool voulu;

  @override
  Widget build(BuildContext context) {
    final couleurEtat = isConnected
        ? OuroColors.systemGreen
        : isConnecting
            ? OuroColors.systemOrange
            : OuroColors.systemGray;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: OuroColors.secondarySystemGroupedBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isConnected
              ? OuroColors.systemGreen.withValues(alpha: 0.30)
              : OuroColors.separator,
        ),
      ),
      child: Column(
        children: [
          // ── LE CADENAS ────────────────────────────────────────────
          //
          // ⚠️ C'ÉTAIT UN BOUCLIER ENTOURÉ D'UN HALO VERT PULSANT.
          //
          // Deux problèmes. Le halo coloré est explicitement banni par
          // `design_tokens.dart` — « un effet de jeu vidéo, jamais
          // utilisé par Apple, et le marqueur le plus reconnaissable
          // d'une interface amateur ». Et un bouclier ne dit rien du
          // passage d'un état à l'autre : il est vert ou il est gris.
          //
          // Le cadenas, lui, SE FERME. On voit l'anse descendre quand le
          // circuit s'établit, et se rouvrir s'il retombe. C'est le même
          // objet que dans la barre d'état et sur le bouton micro : une
          // seule chose à apprendre pour toute l'application.
          AnimatedBuilder(
            animation: shieldScale,
            builder: (context, child) {
              return Transform.scale(
                scale: shieldScale.value,
                child: Container(
                  width: 80,
                  height: 80,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isConnected
                        ? OuroColors.systemGreen.withValues(alpha: 0.14)
                        : OuroColors.systemGray5,
                  ),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: isConnected ? 1 : 0),
                    duration: DesignTokens.durationSheet,
                    curve: DesignTokens.curveStandard,
                    builder: (context, fermeture, _) => OuroPadlock(
                      fermeture: fermeture,
                      couleur: couleurEtat,
                      taille: 40,
                      epaisseur: 4,
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          // Titre
          Text(
            isConnected
                ? 'Tor actif'
                : isConnecting
                    ? 'Connexion…'
                    : 'Mode privé',
            style: OuroTypography.title2.copyWith(
              color: isConnected || isConnecting
                  ? couleurEtat
                  : OuroColors.label,
            ),
          ),

          const SizedBox(height: 4),

          // Sous-titre
          Text(
            isConnected
                ? 'Vos données passent par le réseau Tor'
                : isConnecting
                    ? 'Établissement du circuit (10-30s)'
                    : 'Protégez votre identité en ligne',
            style: OuroTypography.subheadline.copyWith(
              color: OuroColors.secondaryLabel,
            ),
          ),

          const SizedBox(height: 20),

          // Toggle
          if (generatingAddress)
            const CircularProgressIndicator(strokeWidth: 2)
          else
            // `voulu` et non l'état du circuit : voir le champ.
            // ⚠️ Aucune couleur passée : `activeColor` et
            // `activeTrackColor` ont changé de nom entre deux versions de
            // Flutter, et la valeur par défaut de `CupertinoSwitch` est
            // déjà le vert du système. Un paramètre en moins, une
            // rupture de compilation en moins à la prochaine montée de
            // version.
            CupertinoSwitch(
              value: voulu,
              onChanged: onToggle,
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// STATE ROW ANIMÉE
// ============================================================================

class _AnimatedStateRow extends StatelessWidget {
  const _AnimatedStateRow({required this.state});

  final TorServiceState? state;

  @override
  Widget build(BuildContext context) {
    final (icon, color, text, detail) = switch (state) {
      TorServiceState.connecting => (
          Icons.sync_rounded,
          OuroColors.systemOrange,
          'Connexion…',
          'Établissement du circuit Tor',
        ),
      TorServiceState.connected => (
          Icons.shield_rounded,
          OuroColors.systemGreen,
          'Connecté',
          'Circuit Tor actif — IP masquée',
        ),
      TorServiceState.error => (
          Icons.error_outline_rounded,
          OuroColors.systemRed,
          'Erreur',
          'Vérifiez votre connexion internet',
        ),
      TorServiceState.stopped || null => (
          Icons.shield_outlined,
          OuroColors.systemGray,
          'Éteint',
          'Tor n\'est pas actif',
        ),
    };

    return OuroListRow(
      icon: icon,
      iconColor: color,
      title: text,
      subtitle: detail,
      showChevron: false,
    );
  }
}

// ============================================================================
// BOTTOM SHEET "COMMENT ÇA MARCHE"
// ============================================================================

class _HowItWorksSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OuroColors.secondarySystemGroupedBackground,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Poignée
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: OuroColors.systemGray3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Comment Tor protège vos données',
                  style: OuroTypography.title2,
                ),
                const SizedBox(height: 20),

                _HowItWorksStep(
                  number: '1',
                  icon: Icons.language_rounded,
                  title: 'Circuit chiffré',
                  description: 'Vos messages passent par 3 relais Tor '
                      'dans le monde, chacun ne voyant que le précédent '
                      'et le suivant.',
                ),
                const SizedBox(height: 16),

                _HowItWorksStep(
                  number: '2',
                  icon: Icons.visibility_off_rounded,
                  title: 'IP masquée',
                  description: 'Aucun site, voisin ou fournisseur '
                      'd\'accès ne peut voir votre vraie adresse.',
                ),
                const SizedBox(height: 16),

                _HowItWorksStep(
                  number: '3',
                  icon: Icons.link_rounded,
                  title: 'Mesh préservé',
                  description: 'Le Bluetooth et Wi-Fi local continuent '
                      'de fonctionner normalement.',
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Compris'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  const _HowItWorksStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
  });

  final String number;
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: OuroColors.accent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: OuroTypography.body.copyWith(
                color: OuroColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: OuroTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: OuroTypography.subheadline.copyWith(
                  color: OuroColors.secondaryLabel,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
