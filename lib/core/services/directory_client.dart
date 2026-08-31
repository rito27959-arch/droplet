// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Client pour le serveur directory .onion.
//
// Permet d'enregistrer cet appareil, de chercher des contacts, et de
// se désinscrire de l'annuaire.
// ============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Entrée d'un contact dans l'annuaire.
class DirectoryContact {
  const DirectoryContact({
    required this.peerId,
    required this.pseudo,
    required this.onionAddress,
    required this.publicKey,
  });

  final String peerId;
  final String pseudo;
  final String onionAddress;
  final String publicKey;

  factory DirectoryContact.fromJson(Map<String, dynamic> json) {
    return DirectoryContact(
      peerId: json['peerId'] as String,
      pseudo: json['pseudo'] as String,
      onionAddress: json['onion'] as String,
      publicKey: json['publicKey'] as String,
    );
  }
}

/// Client pour le serveur directory.
///
/// Peut fonctionner directement (serveur classique) ou via Tor (serveur .onion).
class DirectoryClient {
  DirectoryClient({required this.serverUrl, http.Client? httpClient})
      : _client = httpClient ?? http.Client();

  /// URL du serveur (ex: http://xyz.onion:8080 ou https://droplet-directory.up.railway.app).
  final String serverUrl;

  /// Client HTTP sous-jacent — peut être un TorHttpClient ou un client direct.
  final http.Client _client;

  /// Enregistre cet appareil dans l'annuaire.
  Future<bool> register({
    required String peerId,
    required String pseudo,
    required String onionAddress,
    required String publicKey,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$serverUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'peerId': peerId,
          'pseudo': pseudo,
          'onion': onionAddress,
          'publicKey': publicKey,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint('[Directory] Enregistré: $pseudo');
        return true;
      }

      debugPrint('[Directory] Erreur enregistrement: ${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('[Directory] Erreur enregistrement: $e');
      return false;
    }
  }

  /// Se désinscrit de l'annuaire.
  Future<bool> unregister(String peerId) async {
    try {
      final response = await _client.delete(
        Uri.parse('$serverUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'peerId': peerId}),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[Directory] Erreur désinscription: $e');
      return false;
    }
  }

  /// Cherche des contacts par pseudo.
  Future<List<DirectoryContact>> search(String query) async {
    try {
      final response = await _client.get(
        Uri.parse('$serverUrl/search?q=${Uri.encodeComponent(query)}'),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final results = json['results'] as List<dynamic>;
        return results
            .map((e) => DirectoryContact.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      return [];
    } catch (e) {
      debugPrint('[Directory] Erreur recherche: $e');
      return [];
    }
  }

  /// Health check.
  Future<bool> isHealthy() async {
    try {
      final response = await _client.get(Uri.parse('$serverUrl/health'));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Ferme le client HTTP sous-jacent.
  void close() {
    _client.close();
  }
}
