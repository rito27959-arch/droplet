// La marque : l'icône de Droplet Drop (assets/icone.png, tirée de
// docs/icone-source.png par scripts/icones/generer_icones.py), et l'avatar
// des appareils.
import 'package:flutter/material.dart';


class Goutte extends StatelessWidget {
  const Goutte({super.key, this.taille = 40, this.fond = true});

  final double taille;

  /// Gardé pour compatibilité : l'icône a toujours sa tuile.
  final bool fond;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Droplet Drop',
        image: true,
        child: Image.asset('assets/icone.png', width: taille, height: taille, filterQuality: FilterQuality.high),
      );
}

/// L'avatar d'un appareil : l'icône de sa plateforme sur une teinte tirée
/// de son empreinte (toujours la même pour lui).
class AvatarAppareil extends StatelessWidget {
  const AvatarAppareil({super.key, required this.plateforme, required this.empreinte, this.taille = 46});

  final String plateforme;
  final String empreinte;
  final double taille;

  static const _teintes = [
    [Color(0xFF168BFF), Color(0xFF34D8FF)],
    [Color(0xFF4855E8), Color(0xFF8B7CFF)],
    [Color(0xFF12B8E0), Color(0xFF5CF0D4)],
    [Color(0xFF8B5CF6), Color(0xFFD06BFF)],
    [Color(0xFF16B46C), Color(0xFF7BE0A0)],
    [Color(0xFFFF8A3D), Color(0xFFFFC56B)],
  ];

  static IconData icone(String plateforme) => switch (plateforme) {
        'android' => Icons.phone_android_rounded,
        'ios' => Icons.phone_iphone_rounded,
        'macos' => Icons.laptop_mac_rounded,
        'windows' => Icons.desktop_windows_rounded,
        'linux' => Icons.computer_rounded,
        _ => Icons.devices_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final i = empreinte.isEmpty ? 0 : empreinte.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0xffff) % _teintes.length;
    return Container(
      width: taille,
      height: taille,
      // Une tuile aux coins doux, comme les appareils du site.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(taille * 0.3),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _teintes[i]),
        boxShadow: [BoxShadow(color: _teintes[i].first.withValues(alpha: 0.25), blurRadius: taille * 0.3, offset: Offset(0, taille * 0.08))],
      ),
      child: Icon(icone(plateforme), color: Colors.white, size: taille * 0.48),
    );
  }
}
