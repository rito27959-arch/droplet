// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Envoie une vraie notification push via Firebase Cloud Messaging (FCM),
// pour réveiller un appareil dont l'app Droplet n'est plus ouverte —
// « nouveau message », « appel entrant ».
//
// ── Pourquoi ce fichier vit dans l'annuaire, et pas dans la mailbox ou
//    le serveur de signalisation ────────────────────────────────────────
//
// L'annuaire est déjà l'endroit où chaque appareil s'enregistre avec son
// identité — c'est donc le seul des trois petits serveurs Droplet qui
// sait déjà, pour chaque `peerId`, comment le joindre. Y ajouter le
// jeton FCM (voir `register`) et le secret du compte de service Firebase
// évite de dupliquer ce secret sur TROIS serveurs Railway séparés : la
// mailbox et le serveur de signalisation appellent simplement `/notify`
// ici quand ils ont quelque chose à annoncer, sans jamais connaître
// eux-mêmes la clé privée Firebase.
//
// ── Le protocole d'authentification (OAuth2 « JWT bearer ») ───────────
//
// FCM v1 ne prend pas de clé API simple : il faut prouver qu'on EST le
// projet Firebase, avec la clé privée du compte de service. Trois
// étapes :
//   1. Fabriquer un jeton signé (JWT) qui dit « je suis ce compte de
//      service, et je demande la permission d'envoyer des notifications ».
//   2. L'échanger contre un jeton d'accès Google, valable une heure.
//   3. Utiliser ce jeton d'accès pour appeler l'API d'envoi FCM.
// Le jeton d'accès est mis en cache et réutilisé jusqu'à expiration —
// répéter les trois étapes à chaque notification enverrait une requête
// d'authentification pour rien.
// ============================================================================

import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

class FcmSender {
  FcmSender({required Map<String, dynamic> serviceAccountJson})
      : _clientEmail = serviceAccountJson['client_email'] as String,
        _privateKeyPem = serviceAccountJson['private_key'] as String,
        _projectId = serviceAccountJson['project_id'] as String;

  final String _clientEmail;
  final String _privateKeyPem;
  final String _projectId;
  final _client = http.Client();

  String? _jetonAcces;
  DateTime? _expirationJeton;

  /// Échange la clé privée du compte de service contre un jeton d'accès
  /// Google — mis en cache jusqu'à une minute avant son expiration réelle,
  /// par prudence sur les décalages d'horloge entre ce serveur et Google.
  Future<String?> _obtenirJetonAcces() async {
    final jeton = _jetonAcces;
    final expiration = _expirationJeton;
    if (jeton != null && expiration != null && DateTime.now().isBefore(expiration)) {
      return jeton;
    }

    try {
      final jwt = JWT(
        {'scope': 'https://www.googleapis.com/auth/firebase.messaging'},
        issuer: _clientEmail,
        audience: Audience.one('https://oauth2.googleapis.com/token'),
      );
      final assertion = jwt.sign(
        RSAPrivateKey(_privateKeyPem),
        algorithm: JWTAlgorithm.RS256,
        expiresIn: const Duration(hours: 1),
      );

      final reponse = await _client.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': assertion,
        },
      );

      if (reponse.statusCode != 200) {
        print('[FCM] Échec obtention du jeton OAuth2 (${reponse.statusCode}): ${reponse.body}');
        return null;
      }

      final json = jsonDecode(reponse.body) as Map<String, dynamic>;
      final accessToken = json['access_token'] as String;
      final expiresIn = json['expires_in'] as int? ?? 3600;
      _jetonAcces = accessToken;
      _expirationJeton = DateTime.now().add(Duration(seconds: expiresIn - 60));
      return accessToken;
    } catch (e) {
      print('[FCM] Erreur signature/échange du jeton: $e');
      return null;
    }
  }

  /// Envoie un push à un appareil précis.
  ///
  /// ⚠️ DEUX FORMES, ET LA DIFFÉRENCE COMPTE.
  ///
  /// [afficherDirectement] `false` (défaut) → push DATA SEUL : aucun bloc
  /// `notification`, donc Android n'affiche RIEN tout seul et réveille
  /// l'isolate Dart d'arrière-plan (`gererMessageArrierePlan`), qui
  /// construit lui-même la bulle — avec ses boutons « Répondre » /
  /// « Marquer lu ». C'est la seule façon d'avoir une réponse directe
  /// depuis la notification d'un message ou d'un appel reçu app fermée.
  /// [titre]/[corps] sont alors ignorés (le serveur n'a jamais vu le
  /// contenu ; l'app écrit un texte générique honnête).
  ///
  /// [afficherDirectement] `true` → bloc `notification` classique,
  /// affiché par Android sans réveiller de code. Réservé au SEUL cas où
  /// le texte vient VRAIMENT du serveur : l'avertissement de modération.
  ///
  /// Renvoie `false` sans lever d'exception en cas d'échec.
  Future<bool> envoyer({
    required String jetonAppareil,
    required String titre,
    required String corps,
    Map<String, String> data = const {},
    bool afficherDirectement = false,
  }) async {
    final jetonAcces = await _obtenirJetonAcces();
    if (jetonAcces == null) return false;

    final message = <String, dynamic>{
      'token': jetonAppareil,
      'data': donneesPourFcm(data),
      'android': {'priority': 'high'},
    };
    if (afficherDirectement) {
      message['notification'] = {'title': titre, 'body': corps};
      (message['android'] as Map)['notification'] = {
        'channel_id': 'droplet_messages_v2',
      };
    }

    try {
      final reponse = await _client.post(
        Uri.parse('https://fcm.googleapis.com/v1/projects/$_projectId/messages:send'),
        headers: {
          'Authorization': 'Bearer $jetonAcces',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'message': message}),
      );

      if (reponse.statusCode == 200) return true;
      print('[FCM] Échec envoi (${reponse.statusCode}): ${reponse.body}');
      return false;
    } catch (e) {
      print('[FCM] Erreur réseau à l\'envoi: $e');
      return false;
    }
  }

  void close() => _client.close();
}

/// Clés de données interdites par Firebase Cloud Messaging.
///
/// ⚠️ AUCUNE NOTIFICATION N'EST JAMAIS PARTIE À CAUSE DE `from`. La boîte aux
/// lettres et le serveur d'appels envoient l'expéditeur sous `from` ; Firebase
/// refuse tout le message (« Invalid data payload key: from »). Ces clés sont
/// renommées ici — l'application lit `de` aussi bien que `from`.
const _clesReserveesFcm = {'from': 'de', 'notification': 'notif', 'message_type': 'type_message'};

Map<String, String> donneesPourFcm(Map<String, String> data) {
  final resultat = <String, String>{};
  data.forEach((cle, valeur) {
    var nouvelleCle = _clesReserveesFcm[cle] ?? cle;
    // Préfixes réservés, eux aussi refusés.
    if (nouvelleCle.startsWith('google') || nouvelleCle.startsWith('gcm')) {
      nouvelleCle = 'x_$nouvelleCle';
    }
    resultat[nouvelleCle] = valeur;
  });
  return resultat;
}

