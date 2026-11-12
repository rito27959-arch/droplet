// Un « téléphone » Droplet ID en ligne de commande, qui utilise EXACTEMENT
// le protocole de l'app (lib/features/droplet_id/protocole.dart). Sert à
// l'essai de bout en bout en CI.
//
//   dart run tool/droplet_id_appareil.dart <base> <etat.json> creer
//   dart run tool/droplet_id_appareil.dart <base> <etat.json> approuver <demande> <code> <pseudo>
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:droplet/features/droplet_id/protocole.dart';

Future<void> main(List<String> a) async {
  final base = a[0];
  final fichier = File(a[1]);
  final etat = fichier.existsSync() ? jsonDecode(fichier.readAsStringSync()) as Map<String, dynamic> : <String, dynamic>{};
  if (a[2] == 'creer') {
    final graine = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final paire = await Ed25519().newKeyPairFromSeed(graine);
    final pub = await paire.extractPublicKey();
    final r = await requeteSignee(base: base, methode: 'POST', chemin: '/v1/comptes', corps: {'nom': 'CI'}, paire: paire, clePub: b64url(pub.bytes));
    if (r.statut != 201) throw 'creer: ${r.statut} ${r.corps}';
    fichier.writeAsStringSync(jsonEncode({'graine': base64Url.encode(graine), 'appareil': r.corps['appareil_id']}));
    stdout.writeln('ok');
    return;
  }
  final paire = await Ed25519().newKeyPairFromSeed(base64Url.decode(etat['graine'] as String));
  final id = a[3];
  final lu = await requeteSignee(base: base, methode: 'GET', chemin: '/v1/demandes/$id', paire: paire, appareilId: etat['appareil'] as String);
  if (lu.statut != 200) throw 'lire: ${lu.statut} ${lu.corps}';
  final r = await requeteSignee(
    base: base, methode: 'POST', chemin: '/v1/demandes/$id/decision',
    corps: {'decision': 'approuver', 'code': a[4], 'portees': ['openid', 'profile'], 'pseudo': a[5]},
    paire: paire, appareilId: etat['appareil'] as String,
  );
  if (r.statut != 200) throw 'decider: ${r.statut} ${r.corps}';
  stdout.writeln(jsonEncode({'site': lu.corps['client']['nom']}));
}
