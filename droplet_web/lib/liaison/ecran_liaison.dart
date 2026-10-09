// L'ÉCRAN DE LIAISON — la première chose qu'on voit sur web.dropletmesh.app.
//
// La grammaire de WhatsApp Web et de l'app Messages sur Mac, à la finition
// d'iOS :
//   • une carte de verre au centre, posée sur le maillage qui respire ;
//   • à gauche, trois étapes numérotées — on sait quoi faire sans lire ;
//   • à droite, le code QR sur son carré blanc (toujours blanc, même en mode
//     sombre : un scanner lit mal un code clair sur fond noir), la goutte au
//     centre, et un fin anneau d'accent qui se vide jusqu'au renouvellement.
//
// Sur un écran étroit (un téléphone qui ouvre le site), on ne montre PAS de
// code : il ne pourrait pas se scanner lui-même. On explique, simplement.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:qr/qr.dart' show QrErrorCorrectLevel;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:web/web.dart' as web;

import '../design/ouro_colors.dart';
import '../design/ouro_typography.dart';
import '../fond/goutte.dart';
import '../fond/maillage.dart';
import '../textes.dart';
import 'invitation_liaison.dart';

/// La courbe de sortie d'Apple : rapide au départ, très douce à l'arrivée.
const Curve kSortie = Cubic(0.16, 1, 0.3, 1);

class EcranLiaison extends StatefulWidget {
  const EcranLiaison({super.key, required this.textes});

  final Textes textes;

  @override
  State<EcranLiaison> createState() => _EcranLiaisonState();
}

class _EcranLiaisonState extends State<EcranLiaison> {
  static const _duree = 60;

  InvitationLiaison? _invitation;
  int _restant = _duree;
  bool _rester = false;
  Timer? _minuteur;

  @override
  void initState() {
    super.initState();
    _renouveler();
    _minuteur = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_restant <= 1) {
        _renouveler();
      } else {
        setState(() => _restant--);
      }
    });
  }

  Future<void> _renouveler() async {
    final nouvelle = await InvitationLiaison.nouvelle();
    if (!mounted) return;
    setState(() {
      _invitation = nouvelle;
      _restant = _duree;
    });
  }

  @override
  void dispose() {
    _minuteur?.cancel();
    super.dispose();
  }

  void _ouvrir(String url) => web.window.open(url, '_blank');

  @override
  Widget build(BuildContext context) {
    final t = widget.textes;
    final largeur = MediaQuery.sizeOf(context).width;
    final etroit = largeur < 760;

    return Scaffold(
      backgroundColor: OuroColors.systemGroupedBackground,
      body: Stack(
        children: [
          Positioned.fill(
            child: FondMaillage(
              couleurPoint: OuroColors.label,
              couleurAccent: OuroColors.accent,
            ),
          ),
          // Un voile radial : le maillage s'efface sous la carte, et le
          // regard va au centre.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.9,
                    colors: [
                      OuroColors.systemGroupedBackground.withValues(alpha: 0.92),
                      OuroColors.systemGroupedBackground.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // La marque en haut à gauche, comme WhatsApp Web.
          Positioned(
            top: 22,
            left: 28,
            child: SafeArea(child: _Marque(textes: t)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
                child: _Apparition(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 36),
                      _CarteVerre(
                        child: etroit
                            ? _GrandEcran(textes: t, onTelecharger: () => _ouvrir('https://dropletmesh.app/'))
                            : _Contenu(
                                textes: t,
                                invitation: _invitation,
                                restant: _restant,
                                duree: _duree,
                                rester: _rester,
                                onRester: (v) => setState(() => _rester = v),
                                onRenouveler: _renouveler,
                              ),
                      ),
                      if (!etroit) ...[
                        const SizedBox(height: 16),
                        _CarteVerre(
                          child: _CarteAndroid(
                            textes: t,
                            onTelecharger: () => _ouvrir('https://dropletmesh.app/'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      _PiedDePage(
                        textes: t,
                        onAide: () => _ouvrir('https://dropletmesh.app/support/'),
                        onTelecharger: () => _ouvrir('https://dropletmesh.app/'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// L'entrée de la page : la carte monte de 18 points et s'éclaircit, sur la
/// courbe de sortie d'Apple.
class _Apparition extends StatelessWidget {
  const _Apparition({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1100),
      curve: kSortie,
      child: child,
      builder: (context, v, enfant) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - v)),
          child: Transform.scale(scale: 0.97 + 0.03 * v, child: enfant),
        ),
      ),
    );
  }
}

class _Marque extends StatelessWidget {
  const _Marque({required this.textes});

  final Textes textes;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Goutte(taille: 30, couleur: OuroColors.accent),
        const SizedBox(width: 10),
        Text(
          textes.titre,
          style: OuroTypography.title2.copyWith(color: OuroColors.label),
        ),
      ],
    );
  }
}

/// La carte de verre : un flou d'arrière-plan, une teinte de surface, un
/// liseré d'un demi-point et une ombre très large — la matière des
/// panneaux de macOS et d'iOS.
class _CarteVerre extends StatelessWidget {
  const _CarteVerre({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const rayon = BorderRadius.all(Radius.circular(28));
    return Container(
      constraints: const BoxConstraints(maxWidth: 940),
      decoration: BoxDecoration(
        borderRadius: rayon,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: OuroColors.isDark ? 0.5 : 0.10),
            blurRadius: 60,
            offset: const Offset(0, 24),
            spreadRadius: -10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: rayon,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: rayon,
              color: OuroColors.secondarySystemGroupedBackground
                  .withValues(alpha: OuroColors.isDark ? 0.78 : 0.82),
              border: Border.all(color: OuroColors.separator, width: 0.5),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Contenu extends StatelessWidget {
  const _Contenu({
    required this.textes,
    required this.invitation,
    required this.restant,
    required this.duree,
    required this.rester,
    required this.onRester,
    required this.onRenouveler,
  });

  final Textes textes;
  final InvitationLiaison? invitation;
  final int restant;
  final int duree;
  final bool rester;
  final ValueChanged<bool> onRester;
  final VoidCallback onRenouveler;

  @override
  Widget build(BuildContext context) {
    final t = textes;
    return Padding(
      padding: const EdgeInsets.fromLTRB(48, 48, 48, 44),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.connexion,
                  style: OuroTypography.title1.copyWith(color: OuroColors.label),
                ),
                const SizedBox(height: 8),
                Text(
                  t.sousTitre,
                  style: OuroTypography.body.copyWith(color: OuroColors.secondaryLabel),
                ),
                const SizedBox(height: 30),
                _Etape(numero: 1, texte: t.etape1),
                const SizedBox(height: 18),
                _Etape(numero: 2, texte: t.etape2),
                const SizedBox(height: 18),
                _Etape(numero: 3, texte: t.etape3),
                const SizedBox(height: 36),
                _Rester(textes: t, valeur: rester, onChanged: onRester),
              ],
            ),
          ),
          const SizedBox(width: 56),
          _BlocQr(
            textes: t,
            invitation: invitation,
            restant: restant,
            duree: duree,
            onRenouveler: onRenouveler,
          ),
        ],
      ),
    );
  }
}

class _Etape extends StatelessWidget {
  const _Etape({required this.numero, required this.texte});

  final int numero;
  final String texte;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: OuroColors.accent.withValues(alpha: 0.14),
          ),
          child: Text(
            '$numero',
            style: OuroTypography.subheadline.copyWith(
              color: OuroColors.accent,
              fontWeight: FontWeight.w600,
              fontVariations: const [FontVariation('wght', 600)],
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              texte,
              style: OuroTypography.body.copyWith(color: OuroColors.label),
            ),
          ),
        ),
      ],
    );
  }
}

class _Rester extends StatelessWidget {
  const _Rester({required this.textes, required this.valeur, required this.onChanged});

  final Textes textes;
  final bool valeur;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CupertinoSwitch(
          value: valeur,
          onChanged: onChanged,
          activeTrackColor: OuroColors.accent,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(textes.rester,
                  style: OuroTypography.subheadline.copyWith(color: OuroColors.label)),
              const SizedBox(height: 2),
              Text(textes.resterAide,
                  style: OuroTypography.footnote.copyWith(color: OuroColors.secondaryLabel)),
            ],
          ),
        ),
      ],
    );
  }
}

class _BlocQr extends StatelessWidget {
  const _BlocQr({
    required this.textes,
    required this.invitation,
    required this.restant,
    required this.duree,
    required this.onRenouveler,
  });

  final Textes textes;
  final InvitationLiaison? invitation;
  final int restant;
  final int duree;
  final VoidCallback onRenouveler;

  static const double _cote = 264;

  @override
  Widget build(BuildContext context) {
    final inv = invitation;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // L'anneau se vide en douceur entre deux secondes, au lieu de
        // sauter d'un cran à chaque tic.
        TweenAnimationBuilder<double>(
          tween: Tween(end: restant / duree),
          duration: const Duration(milliseconds: 950),
          curve: Curves.linear,
          builder: (context, progres, enfant) => CustomPaint(
            painter: _Anneau(progres: progres, couleur: OuroColors.accent, fond: OuroColors.separator),
            child: enfant,
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Container(
              width: _cote,
              height: _cote,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                switchInCurve: kSortie,
                transitionBuilder: (enfant, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(a), child: enfant),
                ),
                child: inv == null
                    ? const Center(key: ValueKey('attente'), child: CupertinoActivityIndicator())
                    : Stack(
                        key: ValueKey(inv.canal),
                        alignment: Alignment.center,
                        children: [
                          Semantics(
                            label: textes.codeLiaison,
                            image: true,
                            child: QrImageView(
                              data: inv.contenuQr,
                              version: QrVersions.auto,
                              errorCorrectionLevel: QrErrorCorrectLevel.H,
                              padding: EdgeInsets.zero,
                              backgroundColor: Colors.white,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.circle,
                                color: Color(0xFF1C1C1E),
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.circle,
                                color: Color(0xFF1C1C1E),
                              ),
                            ),
                          ),
                          // La goutte au centre, sur sa pastille blanche.
                          Container(
                            width: 52,
                            height: 52,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Goutte(taille: 34, couleur: OuroColors.accent),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          textes.renouvele(restant),
          style: OuroTypography.footnote.copyWith(
            color: OuroColors.secondaryLabel,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          minimumSize: const Size(0, 30),
          onPressed: onRenouveler,
          child: Text(
            textes.nouveauCode,
            style: OuroTypography.footnote.copyWith(color: OuroColors.accent),
          ),
        ),
      ],
    );
  }
}

/// L'anneau du temps qui reste : une piste discrète, et l'arc d'accent qui
/// part de midi et se vide dans le sens des aiguilles d'une montre.
class _Anneau extends CustomPainter {
  _Anneau({required this.progres, required this.couleur, required this.fond});

  final double progres;
  final Color couleur;
  final Color fond;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(30),
    ).deflate(1.5);
    final piste = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = fond;
    canvas.drawRRect(r, piste);

    // L'arc suit le contour arrondi : on mesure le tracé et on n'en dessine
    // que la part restante, à partir du haut, au centre.
    final chemin = Path()..addRRect(r);
    final mesure = chemin.computeMetrics().first;
    final total = mesure.length;
    // `addRRect` commence en haut à gauche, après l'arrondi : on décale le
    // départ au milieu du bord du haut.
    final depart = (size.width / 2 - 30);
    final longueur = total * progres.clamp(0.0, 1.0);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = couleur;
    final fin = depart + longueur;
    if (fin <= total) {
      canvas.drawPath(mesure.extractPath(depart, fin), arc);
    } else {
      canvas.drawPath(mesure.extractPath(depart, total), arc);
      canvas.drawPath(mesure.extractPath(0, fin - total), arc);
    }
  }

  @override
  bool shouldRepaint(_Anneau ancien) =>
      ancien.progres != progres || ancien.couleur != couleur || ancien.fond != fond;
}

/// La seconde carte, sous celle du code : pour qui n'a pas encore l'app.
class _CarteAndroid extends StatelessWidget {
  const _CarteAndroid({required this.textes, required this.onTelecharger});

  final Textes textes;
  final VoidCallback onTelecharger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 22),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: OuroColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Goutte(taille: 30, couleur: OuroColors.accent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(textes.androidTitre,
                    style: OuroTypography.headline.copyWith(color: OuroColors.label)),
                const SizedBox(height: 2),
                Text(textes.androidTexte,
                    style: OuroTypography.subheadline.copyWith(color: OuroColors.secondaryLabel)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: OuroColors.accent,
            borderRadius: BorderRadius.circular(999),
            onPressed: onTelecharger,
            child: Text(
              textes.telecharger,
              style: OuroTypography.subheadline.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sur un téléphone : pas de code à scanner, une explication.
class _GrandEcran extends StatelessWidget {
  const _GrandEcran({required this.textes, required this.onTelecharger});

  final Textes textes;
  final VoidCallback onTelecharger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.desktopcomputer, size: 44, color: OuroColors.accent),
          const SizedBox(height: 18),
          Text(
            textes.sousTitre,
            textAlign: TextAlign.center,
            style: OuroTypography.title3.copyWith(color: OuroColors.label),
          ),
          const SizedBox(height: 10),
          Text(
            textes.grandEcran,
            textAlign: TextAlign.center,
            style: OuroTypography.body.copyWith(color: OuroColors.secondaryLabel),
          ),
        ],
      ),
    );
  }
}

class _PiedDePage extends StatelessWidget {
  const _PiedDePage({required this.textes, required this.onAide, required this.onTelecharger});

  final Textes textes;
  final VoidCallback onAide;
  final VoidCallback onTelecharger;

  @override
  Widget build(BuildContext context) {
    final discret = OuroTypography.footnote.copyWith(color: OuroColors.secondaryLabel);
    final lien = OuroTypography.footnote.copyWith(color: OuroColors.accent);
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.lock_fill, size: 13, color: OuroColors.secondaryLabel),
            const SizedBox(width: 6),
            Text(textes.chiffre, style: discret),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(textes.pasEncore, style: discret),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 28),
              onPressed: onTelecharger,
              child: Text(textes.telecharger, style: lien),
            ),
            Text('·', style: discret),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 28),
              onPressed: onAide,
              child: Text(textes.aide, style: lien),
            ),
          ],
        ),
      ],
    );
  }
}

