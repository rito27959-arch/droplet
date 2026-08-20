// ============================================================================
// L'OUTIL DE LICENCES — à garder pour vous, jamais dans l'application.
// ----------------------------------------------------------------------------
//   dart run tool/licence.dart cles                 → fabrique la paire de clés
//   dart run tool/licence.dart signer <code> pack   → délivre une licence
//   dart run tool/licence.dart signer <code> pro
//
// ── ⚠️ POURQUOI UNE SIGNATURE, ET PAS UN MOT DE PASSE ─────────────────
//
// Droplet n'a aucun serveur. Il n'y a donc personne à qui demander
// « cette personne a-t-elle payé ? » : l'application doit pouvoir en
// juger seule, hors ligne, sans jamais rien contacter.
//
// La solution naïve — un code secret partagé, caché dans l'application —
// ne tient pas dix minutes : n'importe qui peut ouvrir un APK et y lire
// les chaînes de caractères. Le premier acheteur publierait le code, et
// tout le monde débloquerait gratuitement.
//
// On signe donc chaque licence avec une clé privée que vous êtes SEUL à
// détenir. L'application n'embarque que la clé PUBLIQUE, qui ne permet
// que de vérifier — jamais de fabriquer. Un curieux qui la lit dans
// l'APK n'en tire rien.
//
// ── ⚠️ ET POURQUOI LA LICENCE EST LIÉE À L'APPAREIL ───────────────────
//
// La signature porte sur l'identifiant de l'appareil. Une licence
// délivrée pour le téléphone d'Amina ne débloque donc rien sur celui de
// Michel : le code peut circuler sur WhatsApp, il ne sert à personne
// d'autre. C'est ce qui rend le partage de code inutile — la seule
// fraude qui compte vraiment à cette échelle.
//
// ── Ce que ça ne protège PAS, et il faut le savoir ────────────────────
//
// Quelqu'un qui décompile l'application peut retirer la vérification et
// se fabriquer une version débloquée. C'est vrai de TOUTE application
// hors ligne, sans exception — y compris des plus grandes. On élève le
// mur assez haut pour que ça ne vaille pas 500 F d'effort ; on ne
// prétend pas le rendre infranchissable.
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

const String _prefixe = 'DROP1';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _aide();
    exit(64);
  }

  switch (args.first) {
    case 'cles':
      await _fabriquerLesCles();
    case 'signer':
      if (args.length < 3) {
        _aide();
        exit(64);
      }
      await _signer(args[1], args[2]);
    case 'repondre':
      await _repondre();
    default:
      _aide();
      exit(64);
  }
}

/// Lit le message WhatsApp collé, en tire le code et l'offre, et écrit
/// la réponse toute prête.
///
/// ── ⚠️ POURQUOI CETTE COMMANDE EXISTE ─────────────────────────────
///
/// La commande `signer` demande de RECOPIER un code de seize caractères
/// hexadécimaux depuis un message. C'est exactement le genre de geste où
/// l'on intervertit deux caractères sans s'en apercevoir — et une
/// licence signée pour `a1b2c3d4e5f60781` au lieu de `…0718` est
/// parfaitement valable, parfaitement inutile, et le symptôme apparaît
/// chez quelqu'un qui vient de payer.
///
/// Ici on colle le message tel quel. Le code est EXTRAIT, jamais
/// retapé, et l'offre est déduite du texte. La réponse sort formatée,
/// prête à être renvoyée.
Future<void> _repondre() async {
  stdout.writeln('Collez le message reçu, puis Ctrl+D :\n');
  // On lit tout ce qui arrive jusqu'à la fin de l'entrée : un message
  // WhatsApp tient sur plusieurs lignes, `readLineSync` n'en prendrait
  // qu'une et perdrait justement le code.
  final tampon = StringBuffer();
  String? ligne;
  while ((ligne = stdin.readLineSync()) != null) {
    tampon.writeln(ligne);
  }
  final message = tampon.toString();

  // Le code d'appareil : seize caractères hexadécimaux, avec ou sans
  // tirets. On prend la première occurrence qui a la bonne forme.
  final trouve = RegExp(
    r'\b([0-9a-fA-F]{4})-?([0-9a-fA-F]{4})-?([0-9a-fA-F]{4})-?([0-9a-fA-F]{4})\b',
  ).firstMatch(message);

  if (trouve == null) {
    stderr.writeln('\nAucun code d\'appareil trouvé dans ce message.\n'
        'Attendu : seize caractères hexadécimaux, par exemple '
        'a1b2-c3d4-e5f6-0718.');
    exit(65);
  }
  final code = '${trouve[1]}-${trouve[2]}-${trouve[3]}-${trouve[4]}';

  // L'offre : on cherche le mot, puis le montant en repli. Les deux
  // doivent concorder, sinon on demande plutôt que de deviner.
  final bas = message.toLowerCase();
  final ditPro = bas.contains('pro');
  final ditPack = bas.contains('pack');
  final dit1000 = bas.contains('1000');
  final dit500 = bas.contains('500');

  String? genre;
  if (ditPro && !ditPack) {
    genre = 'pro';
  } else if (ditPack && !ditPro) {
    genre = 'pack';
  } else if (dit1000 && !dit500) {
    genre = 'pro';
  } else if (dit500 && !dit1000) {
    genre = 'pack';
  }

  if (genre == null) {
    stderr.writeln('\nOffre indéterminable dans ce message.\n'
        'Relancez à la main : dart run tool/licence.dart signer $code '
        '<pack|pro>');
    exit(65);
  }

  stdout.writeln('\nCode  : $code');
  stdout.writeln('Offre : $genre');
  stdout.writeln('${'─' * 60}\n');

  final licence = await _fabriquer(code, genre);
  final quoi = genre == 'pro' ? 'Droplet Pro' : 'le pack';

  stdout.writeln('Réponse à renvoyer (tout ce qui suit) :\n');
  final trait = '─' * 60;
  stdout.writeln(trait);
  stdout.writeln('Merci ! Voici votre licence pour $quoi.\n');
  stdout.writeln(licence);
  stdout.writeln('\nDans Droplet : Réglages → Droplet Pro → collez-la '
      'dans « J\'ai reçu ma licence ».');
  stdout.writeln('Elle ne fonctionne que sur votre téléphone.');
  stdout.writeln(trait);
}

void _aide() {
  stdout.writeln('''
Usage :
  dart run tool/licence.dart cles
  dart run tool/licence.dart repondre                    ← le plus simple
  dart run tool/licence.dart signer <code-appareil> <pack|pro>

« repondre » lit le message WhatsApp collé, en extrait le code et
l'offre, et écrit la réponse toute prête. Rien à recopier.

La clé privée est lue depuis la variable d'environnement DROPLET_LICENCE_KEY,
ou depuis ~/.droplet-keys/licence.key si elle n'est pas définie.
''');
}

Future<void> _fabriquerLesCles() async {
  final algo = Ed25519();
  final paire = await algo.newKeyPair();
  final privee = await paire.extractPrivateKeyBytes();
  final publique = (await paire.extractPublicKey()).bytes;

  final dossier = Directory('${Platform.environment['HOME']}/.droplet-keys');
  if (!dossier.existsSync()) dossier.createSync(recursive: true);
  final fichier = File('${dossier.path}/licence.key');
  fichier.writeAsStringSync(base64Encode(privee));
  // Lisible par vous seul : cette clé vaut tout le système de licences.
  Process.runSync('chmod', ['600', fichier.path]);

  stdout.writeln('''
Clé privée écrite dans ${fichier.path}  (chmod 600)
  ⚠️ NE LA PARTAGEZ JAMAIS, ne la mettez dans aucun dépôt.
     Qui la détient peut délivrer des licences gratuites à volonté.
     Si vous la perdez, toutes les licences déjà délivrées restent
     valides, mais vous ne pourrez plus en émettre de nouvelles.

Clé publique à recopier dans lib/core/services/premium_service.dart :

  static const String _clePublique =
      '${base64Encode(publique)}';
''');
}

Future<void> _signer(String codeAppareil, String genre) async {
  if (genre != 'pack' && genre != 'pro') {
    stderr.writeln('Genre inconnu : $genre (attendu « pack » ou « pro »)');
    exit(64);
  }

  // Le code d'appareil s'affiche par groupes de quatre pour être dicté
  // au téléphone sans se tromper ; on retire la mise en forme avant de
  // signer, sinon un tiret oublié invaliderait la licence.
  final appareil = codeAppareil.replaceAll('-', '').replaceAll(' ', '').toLowerCase();
  if (appareil.length != 16) {
    stderr.writeln('Code appareil invalide : 16 caractères attendus, '
        '${appareil.length} reçus.');
    exit(64);
  }

  final licence = await _fabriquer(appareil, genre);

  stdout.writeln('''
Licence « $genre » pour l'appareil $codeAppareil :

$licence

Envoyez cette ligne entière à la personne. Elle ne fonctionnera que sur
son téléphone.
''');
}

/// Fabrique une licence et la renvoie, sans rien écrire.
Future<String> _fabriquer(String codeAppareil, String genre) async {
  final appareil =
      codeAppareil.replaceAll('-', '').replaceAll(' ', '').toLowerCase();
  final brut =
      Platform.environment['DROPLET_LICENCE_KEY'] ?? _lireCleLocale();
  if (brut == null) {
    stderr.writeln('Aucune clé privée. Lancez d\'abord : '
        'dart run tool/licence.dart cles');
    exit(66);
  }
  final algo = Ed25519();
  final paire = await algo.newKeyPairFromSeed(base64Decode(brut.trim()));
  final charge = jsonEncode({
    'd': appareil,
    'k': genre,
    't': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
  });
  final chargeB64 = base64Url.encode(utf8.encode(charge)).replaceAll('=', '');
  // ⚠️ On signe le préfixe AVEC la charge. Sans lui, une licence d'un
  // futur format pourrait être rejouée dans celui-ci.
  //
  // ⚠️ ET C'EST LA SEULE VOIE DE SIGNATURE DE CET OUTIL. `signer` comme
  // `repondre` passent par ici. Une seconde copie de ces cinq lignes
  // finirait par diverger de celle-ci — et une licence signée sur un
  // format légèrement différent est refusée par l'application sans que
  // rien n'indique pourquoi.
  final signature =
      await algo.sign(utf8.encode('$_prefixe.$chargeB64'), keyPair: paire);
  final sigB64 = base64Url.encode(signature.bytes).replaceAll('=', '');
  return '$_prefixe.$chargeB64.$sigB64';
}

String? _lireCleLocale() {
  final f = File('${Platform.environment['HOME']}/.droplet-keys/licence.key');
  return f.existsSync() ? f.readAsStringSync() : null;
}
