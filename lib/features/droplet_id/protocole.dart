// Le protocole des requêtes signées de Droplet ID, en Dart pur (sans
// Flutter) : utilisé par l'app, et par l'essai de bout en bout en CI.
//
//   texte signé = MÉTHODE \n chemin \n heure \n nonce \n sha256-hex(corps)
//   signature   = Ed25519(clé de l'appareil)  — base64url sans « = »

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

String b64url(List<int> o) => base64Url.encode(o).replaceAll('=', '');

class ReponseDroplet {
  ReponseDroplet(this.statut, this.corps);
  final int statut;
  final Map<String, dynamic> corps;
}

/// Envoie une requête signée. `appareilId` pour un appareil enregistré, ou
/// `clePub` (création du compte).
Future<ReponseDroplet> requeteSignee({
  required String base,
  required String methode,
  required String chemin,
  Map<String, dynamic>? corps,
  required SimpleKeyPair paire,
  String? appareilId,
  String? clePub,
  http.Client? client,
}) async {
  final texte = corps == null ? '' : jsonEncode(corps);
  final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final nonce = b64url(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
  final empreinte = (await Sha256().hash(utf8.encode(texte))).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final sig = await Ed25519().sign(utf8.encode('$methode\n$chemin\n$ts\n$nonce\n$empreinte'), keyPair: paire);
  final entetes = {
    'content-type': 'application/json',
    'x-droplet-ts': '$ts',
    'x-droplet-nonce': nonce,
    'x-droplet-sig': b64url(sig.bytes),
    if (clePub != null) 'x-droplet-cle': clePub else 'x-droplet-appareil': appareilId!,
  };
  final c = client ?? http.Client();
  final uri = Uri.parse('$base$chemin');
  final r = switch (methode) {
    'GET' => await c.get(uri, headers: entetes),
    'DELETE' => await c.delete(uri, headers: entetes),
    _ => await c.post(uri, headers: entetes, body: texte),
  };
  if (client == null) c.close();
  final j = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
  return ReponseDroplet(r.statusCode, j);
}
