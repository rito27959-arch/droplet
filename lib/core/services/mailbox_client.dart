// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Client pour le serveur mailbox .onion.
//
// Permet d'envoyer et récupérer des messages chiffrés pour des contacts
// hors-ligne.
// ============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Un message dans la boîte aux lettres.
class MailboxMessage {
  const MailboxMessage({
    required this.id,
    required this.fromPeerId,
    required this.toPeerId,
    required this.encryptedPayload,
    required this.timestamp,
  });

  final String id;
  final String fromPeerId;
  final String toPeerId;
  final String encryptedPayload;
  final DateTime timestamp;

  factory MailboxMessage.fromJson(Map<String, dynamic> json) {
    return MailboxMessage(
      id: json['id'] as String,
      fromPeerId: json['from'] as String,
      toPeerId: json['to'] as String,
      encryptedPayload: json['payload'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

/// Client pour le serveur mailbox.
///
/// Peut fonctionner directement (serveur classique) ou via Tor (serveur .onion).
class MailboxClient {
  MailboxClient({required this.serverUrl, http.Client? httpClient})
      : _client = httpClient ?? http.Client();

  /// URL du serveur (ex: http://xyz.onion:8081 ou https://droplet-mailbox.up.railway.app).
  final String serverUrl;

  /// Client HTTP sous-jacent — peut être un TorHttpClient ou un client direct.
  final http.Client _client;

  /// Dépose un message chiffré dans la boîte d'un destinataire.
  Future<String?> store({
    required String fromPeerId,
    required String toPeerId,
    required String encryptedPayload,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$serverUrl/messages'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'from': fromPeerId,
          'to': toPeerId,
          'payload': encryptedPayload,
        }),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final msgId = json['id'] as String;
        debugPrint('[Mailbox] Message déposé: $msgId');
        return msgId;
      }

      return null;
    } catch (e) {
      debugPrint('[Mailbox] Erreur dépôt: $e');
      return null;
    }
  }

  /// Récupère tous les messages en attente pour un peer.
  Future<List<MailboxMessage>> fetchAll(String peerId) async {
    try {
      final response = await _client.get(
        Uri.parse('$serverUrl/messages/$peerId'),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final messages = json['messages'] as List<dynamic>;
        return messages
            .map((e) => MailboxMessage.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      return [];
    } catch (e) {
      debugPrint('[Mailbox] Erreur récupération: $e');
      return [];
    }
  }

  /// Supprime un message après l'avoir récupéré.
  Future<bool> acknowledge(String peerId, String messageId) async {
    try {
      final response = await _client.delete(
        Uri.parse('$serverUrl/messages/$peerId/$messageId'),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[Mailbox] Erreur ack: $e');
      return false;
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
