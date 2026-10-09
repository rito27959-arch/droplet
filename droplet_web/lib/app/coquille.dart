// LA COQUILLE DE DROPLET WEB — la disposition de WhatsApp Web, la finition
// d'iOS.
//
//   ┌────┬───────────────┬──────────────────────────────┐
//   │rail│  discussions  │        la discussion         │
//   │    │  recherche    │  (ou l'écran d'accueil vide) │
//   │    │  filtres      │                              │
//   └────┴───────────────┴──────────────────────────────┘
//
// Le rail de gauche reprend les onglets de l'app (Discussions, Actus,
// Appels, Réglages) ; la colonne du milieu, la liste de l'app avec ses
// filtres ; à droite, la discussion, avec ses bulles et sa barre de saisie.
// Sous 900 points de large, une seule colonne à la fois, comme sur iPad en
// portrait.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../design/ouro_colors.dart';
import '../design/ouro_typography.dart';
import '../fond/goutte.dart';
import '../textes.dart';
import 'donnees_apercu.dart';
import 'vue_discussion.dart';

const Curve kSortieApp = Cubic(0.16, 1, 0.3, 1);

class Coquille extends StatefulWidget {
  const Coquille({super.key, required this.textes, this.apercu = false});

  final Textes textes;

  /// Vrai sur l'adresse `?apercu` : des discussions d'exemple, et un
  /// bandeau qui le dit.
  final bool apercu;

  @override
  State<Coquille> createState() => _CoquilleState();
}

enum _Filtre { toutes, nonLues, groupes }

class _CoquilleState extends State<Coquille> {
  late final List<Discussion> _discussions =
      widget.apercu ? discussionsApercu(widget.textes.code) : const [];
  int? _ouverte;
  _Filtre _filtre = _Filtre.toutes;
  String _recherche = '';
  int _onglet = 0;

  List<int> get _visibles {
    final q = _recherche.trim().toLowerCase();
    return [
      for (var i = 0; i < _discussions.length; i++)
        if ((q.isEmpty || _discussions[i].nom.toLowerCase().contains(q)) &&
            switch (_filtre) {
              _Filtre.toutes => true,
              _Filtre.nonLues => _discussions[i].nonLus > 0,
              _Filtre.groupes => _discussions[i].groupe,
            })
          i,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.textes;
    final large = MediaQuery.sizeOf(context).width >= 900;
    final liste = _ColonneListe(
      textes: t,
      discussions: _discussions,
      visibles: _visibles,
      ouverte: _ouverte,
      filtre: _filtre,
      onFiltre: (f) => setState(() => _filtre = f),
      onRecherche: (q) => setState(() => _recherche = q),
      onOuvrir: (i) => setState(() => _ouverte = i),
    );
    final droite = _ouverte == null
        ? _AccueilVide(textes: t)
        : VueDiscussion(
            key: ValueKey(_ouverte),
            textes: t,
            discussion: _discussions[_ouverte!],
            onRetour: large ? null : () => setState(() => _ouverte = null),
          );

    return Scaffold(
      backgroundColor: OuroColors.systemGroupedBackground,
      body: Column(
        children: [
          if (widget.apercu) _BandeauApercu(texte: t.apercu),
          Expanded(
            child: large
                ? Row(
                    children: [
                      _Rail(textes: t, onglet: _onglet, onOnglet: (i) => setState(() => _onglet = i)),
                      SizedBox(width: 400, child: liste),
                      VerticalDivider(width: 0.5, thickness: 0.5, color: OuroColors.separator),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 380),
                          switchInCurve: kSortieApp,
                          transitionBuilder: (enfant, a) => FadeTransition(
                            opacity: a,
                            child: SlideTransition(
                              position: Tween(begin: const Offset(0.02, 0), end: Offset.zero).animate(a),
                              child: enfant,
                            ),
                          ),
                          child: droite,
                        ),
                      ),
                    ],
                  )
                : (_ouverte == null ? liste : droite),
          ),
        ],
      ),
    );
  }
}

class _BandeauApercu extends StatelessWidget {
  const _BandeauApercu({required this.texte});

  final String texte;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      color: OuroColors.accent.withValues(alpha: 0.12),
      child: Text(
        texte,
        textAlign: TextAlign.center,
        style: OuroTypography.footnote.copyWith(color: OuroColors.accent),
      ),
    );
  }
}

// ── Le rail ──────────────────────────────────────────────────────────────

class _Rail extends StatelessWidget {
  const _Rail({required this.textes, required this.onglet, required this.onOnglet});

  final Textes textes;
  final int onglet;
  final ValueChanged<int> onOnglet;

  @override
  Widget build(BuildContext context) {
    final items = [
      (CupertinoIcons.chat_bubble_fill, CupertinoIcons.chat_bubble, textes.discussions),
      (Icons.podcasts_rounded, Icons.podcasts_outlined, textes.actus),
      (CupertinoIcons.phone_fill, CupertinoIcons.phone, textes.appels),
    ];
    return Container(
      width: 68,
      decoration: BoxDecoration(
        color: OuroColors.secondarySystemGroupedBackground,
        border: Border(right: BorderSide(color: OuroColors.separator, width: 0.5)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 18),
          Goutte(taille: 28, couleur: OuroColors.accent),
          const SizedBox(height: 22),
          for (var i = 0; i < items.length; i++)
            _BoutonRail(
              icone: onglet == i ? items[i].$1 : items[i].$2,
              libelle: items[i].$3,
              actif: onglet == i,
              onTap: () => onOnglet(i),
            ),
          const Spacer(),
          _BoutonRail(
            icone: CupertinoIcons.gear,
            libelle: textes.reglages,
            actif: onglet == 3,
            onTap: () => onOnglet(3),
          ),
          const SizedBox(height: 10),
          const _Avatar(initiale: 'M', couleurs: [Color(0xFFFF9F0A), Color(0xFFFF375F)], taille: 34),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _BoutonRail extends StatefulWidget {
  const _BoutonRail({required this.icone, required this.libelle, required this.actif, required this.onTap});

  final IconData icone;
  final String libelle;
  final bool actif;
  final VoidCallback onTap;

  @override
  State<_BoutonRail> createState() => _BoutonRailState();
}

class _BoutonRailState extends State<_BoutonRail> {
  bool _survol = false;

  @override
  Widget build(BuildContext context) {
    final fond = widget.actif
        ? OuroColors.accent.withValues(alpha: 0.14)
        : (_survol ? OuroColors.tertiarySystemFill : Colors.transparent);
    return Tooltip(
      message: widget.libelle,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _survol = true),
        onExit: (_) => setState(() => _survol = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: kSortieApp,
            margin: const EdgeInsets.symmetric(vertical: 4),
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(12)),
            child: Icon(
              widget.icone,
              size: 22,
              color: widget.actif ? OuroColors.accent : OuroColors.secondaryLabel,
            ),
          ),
        ),
      ),
    );
  }
}

// ── La colonne des discussions ─────────────────────────────────────────

class _ColonneListe extends StatelessWidget {
  const _ColonneListe({
    required this.textes,
    required this.discussions,
    required this.visibles,
    required this.ouverte,
    required this.filtre,
    required this.onFiltre,
    required this.onRecherche,
    required this.onOuvrir,
  });

  final Textes textes;
  final List<Discussion> discussions;
  final List<int> visibles;
  final int? ouverte;
  final _Filtre filtre;
  final ValueChanged<_Filtre> onFiltre;
  final ValueChanged<String> onRecherche;
  final ValueChanged<int> onOuvrir;

  @override
  Widget build(BuildContext context) {
    final t = textes;
    return ColoredBox(
      color: OuroColors.secondarySystemGroupedBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(t.discussions,
                      style: OuroTypography.largeTitle.copyWith(color: OuroColors.label)),
                ),
                _IconeEntete(icone: CupertinoIcons.square_pencil, onTap: () {}),
                _IconeEntete(icone: CupertinoIcons.ellipsis_circle, onTap: () {}),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: CupertinoSearchTextField(
              placeholder: t.rechercher,
              onChanged: onRecherche,
              style: OuroTypography.body.copyWith(color: OuroColors.label),
              backgroundColor: OuroColors.tertiarySystemFill,
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _Puce(texte: t.toutes, actif: filtre == _Filtre.toutes, onTap: () => onFiltre(_Filtre.toutes)),
                _Puce(texte: t.nonLues, actif: filtre == _Filtre.nonLues, onTap: () => onFiltre(_Filtre.nonLues)),
                _Puce(texte: t.groupes, actif: filtre == _Filtre.groupes, onTap: () => onFiltre(_Filtre.groupes)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: visibles.isEmpty
                ? Center(
                    child: Text(t.aucune,
                        style: OuroTypography.subheadline.copyWith(color: OuroColors.secondaryLabel)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: visibles.length,
                    itemBuilder: (context, k) {
                      final i = visibles[k];
                      return _LigneDiscussion(
                        discussion: discussions[i],
                        selectionnee: ouverte == i,
                        onTap: () => onOuvrir(i),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _IconeEntete extends StatelessWidget {
  const _IconeEntete({required this.icone, required this.onTap});

  final IconData icone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.all(8),
      minimumSize: const Size(36, 36),
      onPressed: onTap,
      child: Icon(icone, size: 22, color: OuroColors.accent),
    );
  }
}

class _Puce extends StatelessWidget {
  const _Puce({required this.texte, required this.actif, required this.onTap});

  final String texte;
  final bool actif;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: kSortieApp,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: actif ? OuroColors.accent : OuroColors.tertiarySystemFill,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              texte,
              style: OuroTypography.subheadline.copyWith(
                color: actif ? Colors.white : OuroColors.label,
                fontWeight: actif ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LigneDiscussion extends StatefulWidget {
  const _LigneDiscussion({required this.discussion, required this.selectionnee, required this.onTap});

  final Discussion discussion;
  final bool selectionnee;
  final VoidCallback onTap;

  @override
  State<_LigneDiscussion> createState() => _LigneDiscussionState();
}

class _LigneDiscussionState extends State<_LigneDiscussion> {
  bool _survol = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.discussion;
    final fond = widget.selectionnee
        ? OuroColors.tertiarySystemFill
        : (_survol ? OuroColors.quaternarySystemFill : Colors.transparent);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _survol = true),
      onExit: (_) => setState(() => _survol = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: fond, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              _Avatar(initiale: d.initiale, couleurs: d.couleurs, taille: 50, enLigne: d.enLigne),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            d.nom,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OuroTypography.headline.copyWith(color: OuroColors.label),
                          ),
                        ),
                        Text(
                          d.heure,
                          style: OuroTypography.footnote.copyWith(
                            color: d.nonLus > 0 ? OuroColors.accent : OuroColors.secondaryLabel,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            d.apercu,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: OuroTypography.subheadline.copyWith(color: OuroColors.secondaryLabel),
                          ),
                        ),
                        if (d.epingle && d.nonLus == 0)
                          Icon(CupertinoIcons.pin_fill, size: 13, color: OuroColors.tertiaryLabel),
                        if (d.nonLus > 0)
                          Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            height: 20,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: OuroColors.accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${d.nonLus}',
                              style: OuroTypography.caption1.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
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
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initiale, required this.couleurs, required this.taille, this.enLigne = false});

  final String initiale;
  final List<Color> couleurs;
  final double taille;
  final bool enLigne;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: taille,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: taille,
            height: taille,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: couleurs,
              ),
            ),
            child: Text(
              initiale,
              style: TextStyle(
                fontFamily: OuroTypography.fontFamily,
                fontSize: taille * 0.42,
                fontWeight: FontWeight.w600,
                fontVariations: const [FontVariation('wght', 600)],
                color: Colors.white,
              ),
            ),
          ),
          if (enLigne)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: taille * 0.28,
                height: taille * 0.28,
                decoration: BoxDecoration(
                  color: const Color(0xFF30D158),
                  shape: BoxShape.circle,
                  border: Border.all(color: OuroColors.secondarySystemGroupedBackground, width: 2.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Avatar réutilisé par la vue de discussion.
Widget avatarDiscussion(Discussion d, double taille) =>
    _Avatar(initiale: d.initiale, couleurs: d.couleurs, taille: taille, enLigne: d.enLigne);

// ── L'accueil vide (aucune discussion ouverte) ──────────────────────────

class _AccueilVide extends StatelessWidget {
  const _AccueilVide({required this.textes});

  final Textes textes;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('vide'),
      color: OuroColors.systemGroupedBackground,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Un ordinateur et un téléphone, reliés par la goutte : l'idée de
          // l'appareil associé en une image.
          SizedBox(
            width: 220,
            height: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 0,
                  child: Icon(CupertinoIcons.device_laptop, size: 120, color: OuroColors.tertiaryLabel),
                ),
                Positioned(
                  right: 6,
                  bottom: 12,
                  child: Icon(CupertinoIcons.device_phone_portrait, size: 64, color: OuroColors.tertiaryLabel),
                ),
                Positioned(
                  top: 0,
                  right: 54,
                  child: Goutte(taille: 34, couleur: OuroColors.accent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(textes.titre, style: OuroTypography.title1.copyWith(color: OuroColors.label)),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              textes.videTexte,
              textAlign: TextAlign.center,
              style: OuroTypography.body.copyWith(color: OuroColors.secondaryLabel),
            ),
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.lock_fill, size: 12, color: OuroColors.tertiaryLabel),
              const SizedBox(width: 6),
              Text(textes.chiffre, style: OuroTypography.footnote.copyWith(color: OuroColors.tertiaryLabel)),
            ],
          ),
        ],
      ),
    );
  }
}
