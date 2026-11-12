import 'dart:convert';

import 'package:flutter_appauth/flutter_appauth.dart';

/// L'adresse du service Droplet ID.
const emetteurDropletId = 'https://id.dropletmesh.app';

/// L'environnement de test (comptes de test, aucune donnée réelle).
const emetteurDropletIdTest = 'https://id-test.dropletmesh.app';

/// Ce que votre app reçoit : un identifiant propre à elle, et rien d'autre
/// (sauf le pseudo, si la personne accepte de le partager).
class SessionDropletId {
  const SessionDropletId({
    required this.sub,
    required this.idToken,
    required this.accessToken,
    this.refreshToken,
    this.pseudo,
    this.expireLe,
  });

  /// Identifiant de la personne, propre à VOTRE app. Stable.
  final String sub;
  final String? pseudo;
  final String idToken;
  final String accessToken;
  final String? refreshToken;
  final DateTime? expireLe;
}

class ErreurDropletId implements Exception {
  const ErreurDropletId(this.code, [this.description = '']);
  final String code;
  final String description;
  @override
  String toString() => 'ErreurDropletId($code${description.isEmpty ? '' : ': $description'})';
}

/// Le client Droplet ID. Flux standard « authorization code + PKCE » via
/// AppAuth : la page de connexion s'ouvre dans un onglet sécurisé du
/// navigateur (jamais une WebView), et AppAuth vérifie l'ID token
/// (émetteur, audience, dates, nonce). Le jeton arrive directement du
/// service en HTTPS.
class DropletId {
  DropletId({
    required this.clientId,
    required this.redirectUri,
    this.emetteur = emetteurDropletId,
    List<String> portees = const ['openid'],
    FlutterAppAuth? appAuth,
  })  : portees = portees.contains('openid') ? portees : ['openid', ...portees],
        _appAuth = appAuth ?? const FlutterAppAuth();

  final String clientId;

  /// Adresse de retour enregistrée, avec le schéma déclaré dans
  /// `android/app/build.gradle` (`manifestPlaceholders['appAuthRedirectScheme']`).
  final String redirectUri;
  final String emetteur;
  final List<String> portees;
  final FlutterAppAuth _appAuth;

  /// Ouvre Droplet ID ; la personne approuve dans l'app Droplet ; rend la session.
  Future<SessionDropletId> connecter({String? langue}) async {
    final AuthorizationTokenResponse r;
    try {
      r = await _appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientId,
          redirectUri,
          issuer: emetteur,
          scopes: portees,
          additionalParameters: langue == null ? null : {'ui_locales': langue},
        ),
      );
    } on FlutterAppAuthUserCancelledException {
      throw const ErreurDropletId('annule', 'La personne a fermé la page de connexion.');
    } on FlutterAppAuthPlatformException catch (e) {
      throw ErreurDropletId(e.platformErrorDetails.error ?? 'erreur', e.platformErrorDetails.errorDescription ?? '');
    }
    final idToken = r.idToken;
    final accessToken = r.accessToken;
    if (idToken == null || accessToken == null) throw const ErreurDropletId('jeton', 'réponse incomplète');
    final claims = _claims(idToken);
    final sub = claims['sub'];
    if (sub is! String || claims['iss'] != emetteur) throw const ErreurDropletId('id_token', 'contenu inattendu');
    return SessionDropletId(
      sub: sub,
      pseudo: claims['preferred_username'] as String?,
      idToken: idToken,
      accessToken: accessToken,
      refreshToken: r.refreshToken,
      expireLe: r.accessTokenExpirationDateTime,
    );
  }

  /// Termine aussi la session Droplet ID dans le navigateur.
  Future<void> deconnecter(SessionDropletId session, {String? retour}) async {
    await _appAuth.endSession(EndSessionRequest(
      idTokenHint: session.idToken,
      issuer: emetteur,
      postLogoutRedirectUrl: retour,
    ));
  }

  static Map<String, dynamic> _claims(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) throw const ErreurDropletId('id_token', 'format');
    final texte = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    return jsonDecode(texte) as Map<String, dynamic>;
  }
}
