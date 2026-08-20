// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est le fichier le plus « secret agent » de toute l'app : il s'occupe de
// transformer les messages en charabia illisible pour tout le monde SAUF la
// bonne personne — même si le message passe par plein de téléphones
// intermédiaires en chemin (le mesh relaie les messages de proche en
// proche, un peu comme un jeu de téléphone arabe).
//
// Imagine deux boîtes aux lettres avec un cadenas :
//   - Chacun a SA PROPRE clé secrète, qu'il ne montre JAMAIS à personne
//     (rangée dans un coffre-fort spécial du téléphone).
//   - Chacun a aussi un cadenas PUBLIC, qu'il peut donner à tout le monde
//     sans problème.
//   - La magie des mathématiques (ça s'appelle « X25519 ») permet que : si
//     je combine MA clé secrète avec TON cadenas public, j'obtiens
//     EXACTEMENT le même résultat que toi quand tu combines TA clé secrète
//     avec MON cadenas public — sans que personne n'ait eu besoin
//     d'envoyer sa clé secrète à qui que ce soit ! On appelle ce résultat
//     commun le « secret partagé ».
//   - Ensuite, on utilise ce secret partagé pour vraiment verrouiller
//     (« chiffrer ») et déverrouiller (« déchiffrer ») les messages, avec
//     un coffre-fort appelé AES-256-GCM.
//
// Pour les GROUPES (plusieurs personnes), on utilise une astuce différente :
// une combinaison de cadenas qui CHANGE TOUTE SEULE après chaque message
// (comme un cliquet qui ne peut tourner que dans un sens) — c'est le
// « ratchet sender-key », expliqué plus bas.
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Chiffrement de bout en bout pour Droplet.
///
/// - Identité par appareil : paire de clés X25519, clé privée en stockage
///   sécurisé (Keychain/Keystore), jamais en base SQLite.
/// - Messages 1:1 : secret partagé ECDH(moi, pair) → HKDF → clé symétrique
///   AES-256-GCM, un nonce aléatoire par message.
/// - Messages de groupe : ratchet "sender-key" (chain key symétrique par
///   membre, dérivation HMAC à chaque message), voir [ratchetForward] /
///   [fastForward].
class CryptoService {
  // `FlutterSecureStorage` est un coffre-fort spécial fourni par le
  // téléphone (Keychain sur iOS, Keystore sur Android) — beaucoup plus
  // protégé qu'un fichier normal ou que la base de données SQLite. C'est
  // là, et SEULEMENT là, qu'on range la clé secrète d'identité.
  static const _secureStorage = FlutterSecureStorage();
  static const _identityPrivateKeyKey = 'identity_x25519_private';

  static final _x25519 = X25519();
  static final _aesGcm = AesGcm.with256bits();
  static final _hmac = Hmac.sha256();

  /// Cache mémoire des secrets partagés dérivés par pair (évite de refaire
  /// l'ECDH+HKDF à chaque message).
  ///
  /// Recalculer le secret partagé à chaque message serait comme refaire le
  /// calcul de multiplication à chaque fois qu'on en a besoin au lieu de
  /// se souvenir du résultat — ça marcherait, mais ce serait lent pour
  /// rien. On le calcule donc une fois, puis on le garde en mémoire.
  ///
  /// Cache de type LRU borné à [_sharedKeyCacheCap] entrées : sur un mesh à
  /// grande échelle on rencontre des dizaines de milliers de pairs au fil
  /// des semaines, et garder un secret par pair sans jamais rien oublier
  /// finirait par dévorer la RAM. Les pairs qu'on n'a plus contactés
  /// depuis longtemps sont les premiers évincés ; on redérivera leur clé
  /// (un seul ECDH) si on les recroise.
  static final Map<String, SecretKey> _sharedKeyCache = <String, SecretKey>{};
  static const int _sharedKeyCacheCap = 512;

  // -- Identité ---------------------------------------------------------

  /// Génère (si absente) la paire de clés X25519 de cet appareil et
  /// retourne la clé publique encodée en base64.
  ///
  /// Autrement dit : « est-ce que j'ai déjà mon cadenas + ma clé secrète ?
  /// Si non, j'en fabrique une nouvelle paire. Dans tous les cas, je donne
  /// mon cadenas (public, sans danger à partager) à qui le demande. »
  static Future<String> ensureIdentityKeyPair() async {
    final existing = await _secureStorage.read(key: _identityPrivateKeyKey);
    if (existing != null) {
      final keyPair = await _keyPairFromStoredPrivate(existing);
      final publicKey = await keyPair.extractPublicKey();
      return base64Encode(publicKey.bytes);
    }

    final keyPair = await _x25519.newKeyPair();
    final privateBytes = await keyPair.extractPrivateKeyBytes();
    await _secureStorage.write(
      key: _identityPrivateKeyKey,
      value: base64Encode(privateBytes),
    );
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  static Future<SimpleKeyPair?> _loadIdentityKeyPair() async {
    final stored = await _secureStorage.read(key: _identityPrivateKeyKey);
    if (stored == null) return null;
    return _keyPairFromStoredPrivate(stored);
  }

  static Future<SimpleKeyPair> _keyPairFromStoredPrivate(String b64) async {
    return _x25519.newKeyPairFromSeed(base64Decode(b64));
  }

  /// Supprime la clé privée d'identité (réinitialisation complète du profil).
  static Future<void> clearIdentity() async {
    await _secureStorage.delete(key: _identityPrivateKeyKey);
    _sharedKeyCache.clear();
  }

  // -- Sauvegarde / restauration d'identité --------------------------------

  /// Exporte le seed de la clé privée d'identité (base64), pour inclusion
  /// dans une sauvegarde chiffrée par mot de passe. Ne quitte l'appareil que
  /// dans un fichier lui-même chiffré — jamais en clair.
  static Future<String?> exportPrivateKeySeed() {
    return _secureStorage.read(key: _identityPrivateKeyKey);
  }

  /// Restaure un seed de clé privée précédemment exporté (transfert
  /// d'appareil). Écrase toute identité existante — réservé au flux de
  /// restauration à l'onboarding, jamais utilisé sur une identité active.
  static Future<void> restorePrivateKeySeed(String base64Seed) async {
    await _secureStorage.write(key: _identityPrivateKeyKey, value: base64Seed);
    _sharedKeyCache.clear();
  }

  /// Dérive une clé de chiffrement à partir d'un mot de passe (PBKDF2-HMAC-
  /// SHA256), pour chiffrer/déchiffrer un fichier de sauvegarde. Le sel doit
  /// être aléatoire et stocké en clair dans l'enveloppe de sauvegarde (ce
  /// n'est pas un secret) ; le nombre d'itérations rend un mot de passe
  /// faible coûteux à essayer en force brute sans pénaliser l'utilisateur
  /// légitime (une seule dérivation par export/import, pas par message).
  ///
  /// Un mot de passe humain (« chaton2010 ») est souvent trop simple pour
  /// servir DIRECTEMENT de clé secrète — trop facile à deviner en
  /// l'essayant plein de fois très vite. PBKDF2 transforme ce mot de passe
  /// en le mélangeant 300 000 fois de suite : ça ne prend qu'une fraction
  /// de seconde pour toi qui as le bon mot de passe, mais ça devient bien
  /// trop lent pour quelqu'un qui essaierait de deviner des millions de
  /// mots de passe différents.
  static Future<SecretKey> deriveBackupKey(
    String password,
    Uint8List salt, {
    int iterations = 300000,
  }) async {
    final pbkdf2 = Pbkdf2.hmacSha256(iterations: iterations, bits: 256);
    return pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
  }

  // -- Secret partagé 1:1 -------------------------------------------------

  /// Dérive (ou retourne depuis le cache) la clé symétrique partagée avec
  /// [peerId], connaissant sa clé publique X25519 en base64.
  static Future<SecretKey?> sharedKeyWithPeer(String peerId, String? peerPublicKeyB64) async {
    if (peerPublicKeyB64 == null || peerPublicKeyB64.isEmpty) return null;
    final cached = _sharedKeyCache[peerId];
    if (cached != null) {
      // Marquer « utilisé à l'instant » : le remettre en fin de liste pour
      // qu'il ne soit pas évincé en premier par le LRU.
      _sharedKeyCache.remove(peerId);
      _sharedKeyCache[peerId] = cached;
      return cached;
    }

    final myKeyPair = await _loadIdentityKeyPair();
    if (myKeyPair == null) return null;

    final peerPublicKey = SimplePublicKey(
      base64Decode(peerPublicKeyB64),
      type: KeyPairType.x25519,
    );

    // C'est ICI que se produit la magie décrite tout en haut du fichier :
    // ma clé secrète + son cadenas public = le même résultat que sa clé
    // secrète + mon cadenas public.
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: peerPublicKey,
    );

    // On ne veut jamais utiliser DIRECTEMENT le résultat brut de X25519
    // comme clé de chiffrement — HKDF le retravaille pour en faire une
    // clé bien formée, comme un jus de fruit qu'on filtre avant de le
    // servir.
    final derived = await Hkdf(
      hmac: _hmac,
      outputLength: 32,
    ).deriveKey(
      secretKey: sharedSecret,
      info: utf8.encode('droplet-1to1-v1'),
      nonce: utf8.encode('droplet-mesh'),
    );

    if (_sharedKeyCache.length >= _sharedKeyCacheCap) {
      _sharedKeyCache.remove(_sharedKeyCache.keys.first);
    }
    _sharedKeyCache[peerId] = derived;
    return derived;
  }

  /// Invalide le secret mis en cache pour [peerId] (ex. clé publique changée).
  static void invalidateSharedKey(String peerId) {
    _sharedKeyCache.remove(peerId);
  }

  // -- AEAD générique (octets bruts) ----------------------------------------
  //
  // « AEAD » veut dire : ça chiffre le message ET ça ajoute un petit
  // tampon de cire au bout, qui prouve que personne n'a modifié le
  // message en chemin (si quelqu'un triche, le tampon ne correspond plus
  // et on rejette le message).

  /// Chiffre [plaintext] avec [key]. Retourne le ciphertext (avec tag MAC
  /// concaténé) et le nonce, en octets bruts — pas de base64, pour éviter le
  /// surcoût sur des payloads volumineux (photos, messages vocaux).
  static Future<(Uint8List cipher, Uint8List nonce)> encryptBytes(SecretKey key, Uint8List plaintext) async {
    // Le « nonce » (« number used once ») est un nombre tiré au hasard à
    // CHAQUE message. Sans lui, verrouiller deux fois le même message
    // donnerait exactement le même résultat chiffré — ce qui laisserait
    // deviner que c'est le même message, même sans le lire. Avec un
    // nonce différent à chaque fois, le même message chiffré deux fois
    // ne se ressemble jamais.
    final nonce = _aesGcm.newNonce();
    final box = await _aesGcm.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
    );
    final combined = Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
    return (combined, Uint8List.fromList(nonce));
  }

  /// Déchiffre le résultat de [encryptBytes]. Retourne null si le
  /// déchiffrement échoue (clé inconnue, tag invalide, message altéré).
  static Future<Uint8List?> decryptBytes(SecretKey key, Uint8List cipher, Uint8List nonce) async {
    try {
      if (cipher.length < 16) return null;
      final cipherText = cipher.sublist(0, cipher.length - 16);
      final macBytes = cipher.sublist(cipher.length - 16);
      final box = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
      final clear = await _aesGcm.decrypt(box, secretKey: key);
      return Uint8List.fromList(clear);
    } catch (_) {
      // Si ça ne déchiffre pas, on ne sait pas POURQUOI exactement (mauvaise
      // clé ? message trafiqué ?) — et ce n'est pas grave : dans les deux
      // cas, la bonne réaction est la même : ignorer proprement ce message
      // plutôt que de planter.
      return null;
    }
  }

  // -- AEAD générique (texte / enveloppe JSON) ------------------------------

  /// Chiffre [plaintext] avec [key]. Retourne (ciphertext, nonce), tous deux
  /// en base64, prêts à être placés dans l'enveloppe JSON du protocole.
  ///
  /// « base64 » = une façon d'écrire des données binaires (des 0 et des 1)
  /// avec seulement des lettres et des chiffres, pour pouvoir les glisser
  /// facilement dans un texte JSON classique.
  static Future<(String cipherB64, String nonceB64)> encrypt(SecretKey key, String plaintext) async {
    final (cipher, nonce) = await encryptBytes(key, Uint8List.fromList(utf8.encode(plaintext)));
    return (base64Encode(cipher), base64Encode(nonce));
  }

  /// Déchiffre le résultat de [encrypt]. Retourne null si le déchiffrement
  /// échoue (clé inconnue, tag invalide, message altéré).
  static Future<String?> decrypt(SecretKey key, String cipherB64, String nonceB64) async {
    try {
      final clear = await decryptBytes(key, base64Decode(cipherB64), base64Decode(nonceB64));
      return clear == null ? null : utf8.decode(clear);
    } catch (_) {
      return null;
    }
  }

  // -- Ratchet sender-key (groupes) ---------------------------------------
  //
  // Pour un groupe, utiliser UN SEUL secret partagé pour tout le monde
  // serait risqué : si une seule personne quitte le groupe (ou perd son
  // téléphone), il faudrait tout changer. À la place, chaque membre a sa
  // propre « chain key » (clé de chaîne) qui avance TOUTE SEULE, comme un
  // compteur kilométrique qui ne peut qu'augmenter : à chaque nouveau
  // message, on en tire une clé de message JETABLE, puis on passe à la
  // chain key suivante — sans jamais pouvoir revenir en arrière. C'est ce
  // qu'on appelle un « ratchet » (un cliquet).

  /// Génère une nouvelle chain key aléatoire (256 bits) pour une sender-key
  /// de groupe.
  static Future<String> generateChainKey() async {
    final key = await _aesGcm.newSecretKey();
    final bytes = await key.extractBytes();
    return base64Encode(bytes);
  }

  /// Avance le ratchet d'un cran : dérive la clé de message courante et la
  /// prochaine chain key à partir de la chain key actuelle (HMAC-based KDF).
  ///
  /// À partir d'UNE chain key, on fabrique DEUX choses différentes (grâce à
  /// deux « étiquettes » différentes, `'message'` et `'chain'`) : la clé qui
  /// sert à chiffrer CE message précis, et la chain key qui servira au
  /// PROCHAIN message. Connaître la clé de message ne permet absolument
  /// pas de retrouver la chain key suivante (ni de revenir à la
  /// précédente) — le cliquet n'avance que dans un sens.
  static Future<(SecretKey messageKey, String nextChainKeyB64)> ratchetForward(String chainKeyB64) async {
    final chainKeyBytes = base64Decode(chainKeyB64);
    final chainSecretKey = SecretKey(chainKeyBytes);

    final msgMac = await _hmac.calculateMac(
      utf8.encode('message'),
      secretKey: chainSecretKey,
    );
    final nextMac = await _hmac.calculateMac(
      utf8.encode('chain'),
      secretKey: chainSecretKey,
    );

    final messageKey = SecretKey(msgMac.bytes);
    final nextChainKeyB64 = base64Encode(nextMac.bytes);
    return (messageKey, nextChainKeyB64);
  }

  /// Fait avancer le ratchet depuis [fromCounter] (exclu) jusqu'à
  /// [toCounter] (inclus), en retournant la clé de message pour
  /// [toCounter] ainsi que la chain key résultante et les clés
  /// intermédiaires "sautées" (compteur → clé de message base64) à mettre
  /// en cache pour tolérer le désordre du relais multi-hop.
  ///
  /// Sur un réseau mesh, les messages peuvent arriver DANS LE DÉSORDRE
  /// (celui-ci passe par un chemin plus court, celui-là traîne en route).
  /// Si on reçoit le message n°5 avant le n°3, il faut quand même pouvoir
  /// déchiffrer le n°3 quand il arrive enfin — donc on avance le ratchet
  /// « en avance rapide » et on GARDE de côté les clés des messages
  /// sautés, au cas où.
  static Future<({SecretKey messageKey, String nextChainKeyB64, Map<int, String> skipped})> fastForward(
    String chainKeyB64,
    int fromCounter,
    int toCounter, {
    int maxSteps = 1000,
  }) async {
    if (toCounter <= fromCounter) {
      throw ArgumentError('toCounter doit être > fromCounter');
    }
    if (toCounter - fromCounter > maxSteps) {
      // Garde-fou : si quelqu'un annonçait un compteur délirant (message
      // corrompu ou malveillant), on refuse de faire tourner le ratchet
      // des milliers de fois pour rien plutôt que de bloquer l'app.
      throw StateError('Trop de messages sautés (${toCounter - fromCounter} > $maxSteps)');
    }

    String currentChainKey = chainKeyB64;
    final skipped = <int, String>{};
    SecretKey? messageKey;

    for (int counter = fromCounter + 1; counter <= toCounter; counter++) {
      final (msgKey, nextChain) = await ratchetForward(currentChainKey);
      currentChainKey = nextChain;
      if (counter == toCounter) {
        messageKey = msgKey;
      } else {
        final bytes = await msgKey.extractBytes();
        skipped[counter] = base64Encode(bytes);
      }
    }

    return (messageKey: messageKey!, nextChainKeyB64: currentChainKey, skipped: skipped);
  }

  static SecretKey secretKeyFromBase64(String b64) => SecretKey(base64Decode(b64));

  // -- Vérification hors-bande (code de sécurité) --------------------------

  static final _sha256 = Sha256();
  static const int _kSafetyNumberRounds = 5000;
  static const int _kSafetyNumberGroups = 12;

  /// Calcule le "code de sécurité" partagé entre deux identités — un nombre
  /// à 60 chiffres (12 groupes de 5), identique quel que soit le côté qui le
  /// calcule. Permet une vérification hors-bande (QR code) des clés
  /// publiques échangées via le mesh, pour sortir du Trust-On-First-Use pur.
  ///
  /// Comment savoir avec certitude que le « contact » avec qui je discute
  /// est vraiment la bonne personne, et pas quelqu'un qui se fait passer
  /// pour elle sur le réseau ? En vrai, en personne, on peut comparer ce
  /// grand numéro (calculé par les DEUX téléphones séparément) : s'il est
  /// identique des deux côtés, c'est la preuve que les clés échangées sont
  /// bien les bonnes. « Trust-On-First-Use » (« faire confiance dès la
  /// première rencontre ») est la stratégie par défaut, plus simple mais
  /// moins sûre — ce code permet de faire mieux quand on veut être
  /// vraiment certain.
  static Future<String> computeSafetyNumber({
    required String myId,
    required String myPublicKey,
    required String peerId,
    required String peerPublicKey,
  }) async {
    final a = '$myId:$myPublicKey';
    final b = '$peerId:$peerPublicKey';
    // On met toujours les deux identités dans le MÊME ordre (le plus petit
    // texte en premier), pour que le calcul donne exactement le même
    // résultat, peu importe qui des deux le lance.
    final ordered = a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

    List<int> material = utf8.encode(ordered);
    // On mélange 5000 fois de suite (comme pétrir une pâte encore et
    // encore), pour que le résultat final ne ressemble à rien de ce qu'on
    // pourrait deviner à partir du texte de départ.
    for (var round = 0; round < _kSafetyNumberRounds; round++) {
      material = (await _sha256.hash(material)).bytes;
    }

    final extended = await Hkdf(hmac: _hmac, outputLength: _kSafetyNumberGroups * 5).deriveKey(
      secretKey: SecretKey(material),
      info: utf8.encode('droplet-safety-number-v1'),
      nonce: utf8.encode('droplet'),
    );
    final bytes = await extended.extractBytes();

    // Transforme le résultat en 12 petits groupes de 5 chiffres, faciles à
    // lire et à comparer à voix haute — comme un long numéro de téléphone
    // découpé en morceaux.
    final groups = <String>[];
    for (var i = 0; i < _kSafetyNumberGroups; i++) {
      final chunk = bytes.sublist(i * 5, i * 5 + 5);
      int value = 0;
      for (final b in chunk) {
        value = (value << 8) | b;
      }
      groups.add((value % 100000).toString().padLeft(5, '0'));
    }
    return groups.join(' ');
  }
}
