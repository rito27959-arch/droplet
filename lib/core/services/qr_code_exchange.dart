// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Échange d'identité via QR code pour la découverte Tor.
//
// Quand deux appareils veulent se connecter via Tor, ils doivent d'abord
// échanger leurs adresses .onion. Le QR code est le moyen le plus simple :
// un appareil affiche son QR, l'autre le scanne, et hop — ils se connaissent.
//
// ── Format du QR code ──────────────────────────────────────────────
//
// Le payload du QR code est un JSON :
// {
//   "type": "droplet_onion",
//   "version": 1,
//   "id": "abc123...",          // ID crypto de l'appareil
//   "pseudo": "Alice",         // Nom affiché
//   "publicKey": "base64...",  // Clé publique X25519
//   "onion": "xyz.onion"       // Adresse .onion
// }
//
// Le champ "type" permet de distinguer nos QR codes de tout autre QR
// code que l'utilisateur pourrait scanner par erreur.
// ============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'onion_service.dart';
import 'storage_service.dart';
import '../models/mesh_message.dart';

/// Format du QR code Droplet pour Tor.
const String _kQrType = 'droplet_onion';
const int _kQrVersion = 1;

/// Données d'un pair scopées via QR code.
class QrPeerData {
  const QrPeerData({
    required this.peerId,
    required this.pseudo,
    required this.publicKey,
    required this.onionAddress,
  });

  final String peerId;
  final String pseudo;
  final String publicKey;
  final String onionAddress;

  /// Sérialise en JSON pour le QR code.
  Map<String, dynamic> toJson() => {
        'type': _kQrType,
        'version': _kQrVersion,
        'id': peerId,
        'pseudo': pseudo,
        'publicKey': publicKey,
        'onion': onionAddress,
      };

  /// Encode en string JSON.
  String encode() => jsonEncode(toJson());

  /// Désérialise depuis un JSON scanné.
  static QrPeerData? fromJson(Map<String, dynamic> json) {
    if (json['type'] != _kQrType) return null;
    if (json['version'] != _kQrVersion) return null;

    final id = json['id'] as String?;
    final pseudo = json['pseudo'] as String?;
    final pubKey = json['publicKey'] as String?;
    final onion = json['onion'] as String?;

    if (id == null || pseudo == null || pubKey == null || onion == null) {
      return null;
    }

    // Vérifications basiques.
    if (id.isEmpty || pubKey.isEmpty || onion.isEmpty) return null;
    if (!onion.endsWith('.onion')) return null;

    return QrPeerData(
      peerId: id,
      pseudo: pseudo,
      publicKey: pubKey,
      onionAddress: onion,
    );
  }

  /// Décodé depuis une string QR scannée.
  static QrPeerData? decode(String qrString) {
    try {
      final json = jsonDecode(qrString) as Map<String, dynamic>;
      return fromJson(json);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QrPeerData &&
          runtimeType == other.runtimeType &&
          peerId == other.peerId &&
          publicKey == other.publicKey &&
          onionAddress == other.onionAddress;

  @override
  int get hashCode => Object.hash(peerId, publicKey, onionAddress);
}

/// Service d'échange d'identité via QR code.
///
/// Génère les données QR de cet appareil et traite les données scannées
/// d'un autre appareil pour l'enregistrer comme contact Tor.
class QrCodeExchange {
  /// Génère les données QR de cet appareil.
  ///
  /// Contient l'ID crypto, le pseudo, la clé publique et l'adresse .onion.
  static Future<String> generateQrData() async {
    // Récupérer l'identité Tor.
    final onionIdentity = await OnionService.ensureIdentity();

    // Récupérer l'ID et le pseudo de l'appareil.
    final userId = StorageService.currentUser?.id ?? '';
    final pseudo = StorageService.currentUser?.pseudo ?? '—';

    final data = QrPeerData(
      peerId: userId,
      pseudo: pseudo,
      publicKey: onionIdentity.publicKeyBase64,
      onionAddress: onionIdentity.onionAddress,
    );

    return data.encode();
  }

  /// Traite les données QR scannées d'un contact.
  ///
  /// Retourne les données du peer si le QR code est valide, null sinon.
  /// Enregistre automatiquement le contact dans le storage.
  static Future<QrPeerData?> processScannedQr(String qrString) async {
    final peerData = QrPeerData.decode(qrString);
    if (peerData == null) {
      debugPrint('[QrCodeExchange] QR invalide ou non-Droplet');
      return null;
    }

    debugPrint('[QrCodeExchange] Contact scopé: ${peerData.pseudo} '
        '(${peerData.onionAddress.substring(0, 12)}…)');

    // Enregistrer le pair dans le storage.
    StorageService.upsertPeer(PeerRecord(
      peerId: peerData.peerId,
      pseudo: peerData.pseudo,
      role: 'leaf',
      transports: ['tor'],
      platform: 'unknown',
      interestGroups: [],
      reliability: 1.0,
      lastSeen: DateTime.now(),
      totalMessagesExchanged: 0,
      publicKey: peerData.publicKey,
      verified: false,
    ));

    return peerData;
  }

  /// Vérifie si une string QR est un QR code Droplet Tor.
  static bool isDropletOnionQr(String qrString) {
    try {
      final json = jsonDecode(qrString) as Map<String, dynamic>;
      return json['type'] == _kQrType && json['version'] == _kQrVersion;
    } catch (_) {
      return false;
    }
  }
}
