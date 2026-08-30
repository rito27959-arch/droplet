// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LA SYNCHRONISATION DIFFÉRENTIELLE : comment deux téléphones qui se
// croisent se mettent d'accord sur ce qu'il faut s'échanger, sans se
// renvoyer tout ce qu'ils possèdent déjà.
//
// ── Le problème ───────────────────────────────────────────────────────
//
// Aujourd'hui, quand Droplet rencontre quelqu'un, il rediffuse ses
// annonces — toutes, à chaque rencontre, que l'autre les ait déjà ou
// non. À deux appareils, c'est invisible. À vingt, chacun renvoie tout à
// tout le monde : le trafic croît comme le CARRÉ du nombre de nœuds,
// alors que l'information nouvelle, elle, n'a pas bougé.
//
// Sur un réseau Bluetooth à quelques kilo-octets par seconde, c'est la
// différence entre une synchronisation qui prend deux secondes et une
// qui n'aboutit jamais avant que les gens se soient éloignés.
//
// ── Le principe : proposer avant d'envoyer ────────────────────────────
//
//     A possède   M1 M2 M3 M4 M5 M6
//     B possède   M1 M2       M4
//
//     A → B   OFFRE    « j'ai M1 M2 M3 M4 M5 M6 »
//     B → A   DEMANDE  « envoie-moi M3 M5 M6 »
//     A → B   les trois messages, et eux seuls
//
// Le coût de l'offre est un identifiant par message (16 octets), au lieu
// du message entier. Pour un vocal de 40 ko, c'est 2500 fois moins.
//
// ── Ce que ce fichier N'EST PAS ───────────────────────────────────────
//
// Il ne parle à aucun réseau et ne touche à aucune base. Ce sont des
// fonctions PURES : on leur donne « ce que j'ai » et « ce qu'on me
// propose », elles répondent « voilà ce que je demande ». C'est ce qui
// permet de mesurer exactement combien d'octets une stratégie coûte,
// sans radio et sans téléphone — et donc de le CHIFFRER plutôt que de
// l'affirmer.
// ============================================================================

import 'dart:typed_data';

/// Nombre maximal d'identifiants dans une seule offre ou demande.
///
/// Une offre voyage dans un paquet. Au-delà de cette taille, elle ne
/// tiendrait plus dans une trame Bluetooth et serait fragmentée — ce qui
/// multiplierait les allers-retours au lieu de les économiser. La
/// synchronisation se fait alors en plusieurs tours, ce qui est
/// exactement le comportement souhaité : on avance par paquets, et une
/// interruption ne fait perdre qu'un tour.
const int kMaxIdsParOffre = 64;

/// Longueur d'un identifiant sur le fil.
///
/// Droplet fabrique ses identifiants avec `Uuid().v4()`, soit 36
/// caractères de texte. Sur le fil, on n'envoie que les 16 octets qu'ils
/// représentent vraiment : les tirets et l'écriture hexadécimale sont
/// une commodité de lecture, pas de l'information.
const int kTailleIdOctets = 16;

/// Ce qu'un nœud propose à un autre.
class SyncOffer {
  const SyncOffer(this.messageIds);

  /// Les identifiants que l'émetteur possède et propose.
  final List<String> messageIds;

  /// Taille de cette offre une fois encodée, en octets.
  int get tailleOctets => 2 + messageIds.length * kTailleIdOctets;

  Uint8List encode() => _encoderIds(messageIds);

  static SyncOffer decode(Uint8List donnees) =>
      SyncOffer(_decoderIds(donnees));
}

/// Ce qu'un nœud réclame en retour.
class SyncRequest {
  const SyncRequest(this.messageIds);

  final List<String> messageIds;

  int get tailleOctets => 2 + messageIds.length * kTailleIdOctets;

  Uint8List encode() => _encoderIds(messageIds);

  static SyncRequest decode(Uint8List donnees) =>
      SyncRequest(_decoderIds(donnees));
}

/// La négociation elle-même — trois fonctions pures.
class SyncNegotiation {
  const SyncNegotiation._();

  /// Ce que J'AI et que je propose, sachant ce que l'autre a déjà.
  ///
  /// [dejaConnusDuPair] permet de ne pas proposer ce qu'on sait déjà
  /// arrivé chez lui — l'accusé de réception d'un tour précédent, par
  /// exemple. Un ensemble vide reste correct, simplement moins économe.
  static SyncOffer preparerOffre({
    required Iterable<String> mesMessages,
    Set<String> dejaConnusDuPair = const {},
    int maxIds = kMaxIdsParOffre,
  }) {
    final aProposer = <String>[];
    for (final id in mesMessages) {
      if (dejaConnusDuPair.contains(id)) continue;
      aProposer.add(id);
      if (aProposer.length >= maxIds) break;
    }
    return SyncOffer(aProposer);
  }

  /// Ce que je DEMANDE, parmi ce qu'on me propose.
  ///
  /// C'est la ligne qui remplace la rediffusion aveugle : on ne réclame
  /// que ce qu'on n'a pas.
  static SyncRequest repondreAOffre({
    required SyncOffer offre,
    required Set<String> mesMessages,
  }) {
    return SyncRequest([
      for (final id in offre.messageIds)
        if (!mesMessages.contains(id)) id,
    ]);
  }

  /// Ce que j'ENVOIE, parmi ce qu'on me demande.
  ///
  /// On refiltre par ce qu'on possède réellement : un pair malveillant
  /// ou simplement désynchronisé pourrait réclamer n'importe quoi, et
  /// une demande n'est pas un ordre.
  static List<String> messagesAEnvoyer({
    required SyncRequest demande,
    required Set<String> mesMessages,
  }) {
    return [
      for (final id in demande.messageIds)
        if (mesMessages.contains(id)) id,
    ];
  }
}

// ─────────────────────────────────────────────────────────────
//  ENCODAGE
// ─────────────────────────────────────────────────────────────

/// Compte sur deux octets, puis les identifiants en binaire.
Uint8List _encoderIds(List<String> ids) {
  final sortie = Uint8List(2 + ids.length * kTailleIdOctets);
  sortie[0] = (ids.length >> 8) & 0xFF;
  sortie[1] = ids.length & 0xFF;
  var pos = 2;
  for (final id in ids) {
    sortie.setRange(pos, pos + kTailleIdOctets, _uuidVersOctets(id));
    pos += kTailleIdOctets;
  }
  return sortie;
}

List<String> _decoderIds(Uint8List donnees) {
  if (donnees.length < 2) return const [];
  final nombre = (donnees[0] << 8) | donnees[1];
  final ids = <String>[];
  var pos = 2;
  for (var i = 0; i < nombre; i++) {
    if (pos + kTailleIdOctets > donnees.length) break;
    ids.add(_octetsVersUuid(donnees.sublist(pos, pos + kTailleIdOctets)));
    pos += kTailleIdOctets;
  }
  return ids;
}

/// « 3f2b… » (36 caractères) → 16 octets.
///
/// Tout identifiant qui n'est pas un UUID valide est ramené à 16 octets
/// par troncature ou remplissage : la négociation doit rester robuste
/// face à un pair qui enverrait n'importe quoi, sans lever d'exception
/// au milieu d'une synchronisation.
Uint8List _uuidVersOctets(String uuid) {
  final hex = uuid.replaceAll('-', '');
  final sortie = Uint8List(kTailleIdOctets);
  for (var i = 0; i < kTailleIdOctets; i++) {
    final debut = i * 2;
    if (debut + 2 > hex.length) break;
    sortie[i] = int.tryParse(hex.substring(debut, debut + 2), radix: 16) ?? 0;
  }
  return sortie;
}

String _octetsVersUuid(Uint8List octets) {
  final hex = octets.map((o) => o.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';
}
