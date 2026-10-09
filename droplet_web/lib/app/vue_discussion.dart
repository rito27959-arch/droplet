// LA DISCUSSION OUVERTE — l'en-tête en verre, les bulles, la barre de
// saisie : la même grammaire que l'écran de discussion de l'app.
//
//   • Mes bulles dans la couleur d'accent, celles des autres en gris
//     système ; une petite queue sur la dernière bulle d'une série.
//   • Les heures et les coches DANS la bulle, en bas à droite.
//   • L'en-tête et la barre de saisie flottent en verre au-dessus du fil,
//     qui défile dessous.
//
// En aperçu, « Envoyer » ajoute la bulle localement : rien ne part.
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../design/ouro_colors.dart';
import '../design/ouro_typography.dart';
import '../textes.dart';
import 'coquille.dart' show avatarDiscussion;
import 'donnees_apercu.dart';

class VueDiscussion extends StatefulWidget {
  const VueDiscussion({super.key, required this.textes, required this.discussion, this.onRetour});

  final Textes textes;
  final Discussion discussion;

  /// Sur un écran étroit : revenir à la liste.
  final VoidCallback? onRetour;

  @override
  State<VueDiscussion> createState() => _VueDiscussionState();
}

class _VueDiscussionState extends State<VueDiscussion> {
  late final List<MessageApercu> _messages = [...widget.discussion.messages];
  final _saisie = TextEditingController();
  final _defilement = ScrollController();

  @override
  void dispose() {
    _saisie.dispose();
    _defilement.dispose();
    super.dispose();
  }

  void _envoyer() {
    final texte = _saisie.text.trim();
    if (texte.isEmpty) return;
    final maintenant = TimeOfDay.now();
    setState(() {
      _messages.add(MessageApercu(
        texte,
        deMoi: true,
        heure: '${maintenant.hour.toString().padLeft(2, '0')}:${maintenant.minute.toString().padLeft(2, '0')}',
        lu: false,
      ));
      _saisie.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_defilement.hasClients) {
        _defilement.animateTo(
          _defilement.position.maxScrollExtent,
          duration: const Duration(milliseconds: 420),
          curve: const Cubic(0.16, 1, 0.3, 1),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.discussion;
    final t = widget.textes;
    return ColoredBox(
      color: OuroColors.systemBackground,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _MotifFond(OuroColors.label))),
          Positioned.fill(
            child: ListView.builder(
              controller: _defilement,
              padding: const EdgeInsets.fromLTRB(24, 86, 24, 90),
              itemCount: _messages.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) return _PastilleJour(texte: t.aujourdhui);
                final m = _messages[i - 1];
                final suivant = i < _messages.length ? _messages[i] : null;
                final finDeSerie = suivant == null || suivant.deMoi != m.deMoi;
                return _Bulle(message: m, queue: finDeSerie);
              },
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _Verre(
              bordBas: true,
              child: SizedBox(
                height: 64,
                child: Row(
                  children: [
                    if (widget.onRetour != null)
                      CupertinoButton(
                        padding: const EdgeInsets.only(left: 8),
                        onPressed: widget.onRetour,
                        child: Icon(CupertinoIcons.back, color: OuroColors.accent),
                      )
                    else
                      const SizedBox(width: 20),
                    avatarDiscussion(d, 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.nom, style: OuroTypography.headline.copyWith(color: OuroColors.label)),
                          if (d.enLigne)
                            Text(t.enLigne,
                                style: OuroTypography.caption1.copyWith(color: OuroColors.secondaryLabel)),
                        ],
                      ),
                    ),
                    _Icone(CupertinoIcons.video_camera),
                    _Icone(CupertinoIcons.phone),
                    _Icone(CupertinoIcons.search),
                    const SizedBox(width: 10),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Verre(
              bordBas: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _Icone(CupertinoIcons.plus, taille: 26),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 40),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: OuroColors.tertiarySystemFill,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _saisie,
                                minLines: 1,
                                maxLines: 6,
                                onSubmitted: (_) => _envoyer(),
                                textInputAction: TextInputAction.send,
                                cursorColor: OuroColors.accent,
                                style: OuroTypography.body.copyWith(color: OuroColors.label),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                  hintText: t.message,
                                  hintStyle: OuroTypography.body.copyWith(color: OuroColors.tertiaryLabel),
                                ),
                              ),
                            ),
                            Icon(CupertinoIcons.smiley, size: 22, color: OuroColors.secondaryLabel),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Le bouton se change en flèche d'envoi dès qu'il y a
                    // du texte, comme dans l'app.
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _saisie,
                      builder: (context, valeur, _) {
                        final plein = valeur.text.trim().isNotEmpty;
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (enfant, a) => ScaleTransition(scale: a, child: enfant),
                          child: plein
                              ? GestureDetector(
                                  key: const ValueKey('envoi'),
                                  onTap: _envoyer,
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(color: OuroColors.accent, shape: BoxShape.circle),
                                    child: const Icon(CupertinoIcons.arrow_up, color: Colors.white, size: 22),
                                  ),
                                )
                              : SizedBox(
                                  key: const ValueKey('micro'),
                                  width: 40,
                                  height: 40,
                                  child: Icon(CupertinoIcons.mic, color: OuroColors.secondaryLabel, size: 24),
                                ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Icone extends StatelessWidget {
  const _Icone(this.icone, {this.taille = 22});

  final IconData icone;
  final double taille;

  @override
  Widget build(BuildContext context) => CupertinoButton(
        padding: const EdgeInsets.all(8),
        minimumSize: const Size(38, 38),
        onPressed: () {},
        child: Icon(icone, size: taille, color: OuroColors.accent),
      );
}

/// Le verre des barres : flou, teinte de fond, liseré d'un demi-point.
class _Verre extends StatelessWidget {
  const _Verre({required this.child, required this.bordBas});

  final Widget child;
  final bool bordBas;

  @override
  Widget build(BuildContext context) {
    final trait = BorderSide(color: OuroColors.separator, width: 0.5);
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: OuroColors.secondarySystemGroupedBackground.withValues(alpha: 0.78),
            border: bordBas ? Border(bottom: trait) : Border(top: trait),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _PastilleJour extends StatelessWidget {
  const _PastilleJour({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: OuroColors.tertiarySystemFill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(texte, style: OuroTypography.caption1.copyWith(color: OuroColors.secondaryLabel)),
      ),
    );
  }
}

class _Bulle extends StatelessWidget {
  const _Bulle({required this.message, required this.queue});

  final MessageApercu message;
  final bool queue;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final fond = m.deMoi ? OuroColors.accent : OuroColors.secondarySystemBackground;
    final encre = m.deMoi ? Colors.white : OuroColors.label;
    final discret = m.deMoi ? Colors.white.withValues(alpha: 0.75) : OuroColors.secondaryLabel;
    const r = Radius.circular(19);
    const petit = Radius.circular(6);
    return Align(
      alignment: m.deMoi ? Alignment.centerRight : Alignment.centerLeft,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 360),
        curve: const Cubic(0.16, 1, 0.3, 1),
        builder: (context, v, enfant) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: enfant),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: EdgeInsets.only(bottom: queue ? 10 : 3),
          padding: const EdgeInsets.fromLTRB(13, 8, 11, 7),
          decoration: BoxDecoration(
            color: fond,
            borderRadius: BorderRadius.only(
              topLeft: r,
              topRight: r,
              bottomLeft: !m.deMoi && queue ? petit : r,
              bottomRight: m.deMoi && queue ? petit : r,
            ),
            boxShadow: m.deMoi
                ? null
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 2, offset: const Offset(0, 1))],
          ),
          child: Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            children: [
              Text(m.texte, style: OuroTypography.body.copyWith(color: encre)),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(m.heure, style: OuroTypography.caption2.copyWith(color: discret)),
                    if (m.deMoi) ...[
                      const SizedBox(width: 3),
                      Icon(
                        m.lu ? Icons.done_all_rounded : Icons.done_rounded,
                        size: 15,
                        color: discret,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Le motif du fond de discussion : de très petites gouttes en quinconce,
/// à peine visibles — le papier peint de l'app, en plus discret.
class _MotifFond extends CustomPainter {
  _MotifFond(this.encre);

  final Color encre;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = encre.withValues(alpha: 0.035);
    const pas = 38.0;
    var ligne = 0;
    for (var y = 0.0; y < size.height + pas; y += pas, ligne++) {
      final decalage = ligne.isOdd ? pas / 2 : 0.0;
      for (var x = decalage; x < size.width + pas; x += pas) {
        canvas.drawCircle(Offset(x, y), 1.6, p);
      }
    }
  }

  @override
  bool shouldRepaint(_MotifFond ancien) => ancien.encre != encre;
}
