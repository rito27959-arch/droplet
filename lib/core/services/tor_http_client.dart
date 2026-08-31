// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Client HTTP qui route les requêtes via le proxy SOCKS5 de Tor.
//
// Utilisé par DirectoryClient et MailboxClient pour atteindre les serveurs
// .onion qui ne sont joignables QUE via le réseau Tor.
//
// Pour les serveurs normaux (Railway), pas besoin de ce client — la
// connexion directe suffit.
//
// ── Comment ça marche ? ─────────────────────────────────────────────
//
// 1. Ouvre une connexion TCP vers le proxy SOCKS5 local (127.0.0.1:9050).
// 2. Fait le handshake SOCKS5 (auth none + CONNECT vers .onion).
// 3. Enveloppe dans TLS si l'URL est https://.
// 4. Envoie la requête HTTP sur cette connexion.
// 5. Lit la réponse.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Client HTTP qui route via le proxy SOCKS5 local de Tor.
class TorHttpClient extends http.BaseClient {
  TorHttpClient({required String host, required int port})
      : _proxyHost = host,
        _proxyPort = port;

  final String _proxyHost;
  final int _proxyPort;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;
    final isSecure = uri.scheme == 'https';
    final targetHost = uri.host;
    final targetPort = uri.port == 0 ? (isSecure ? 443 : 80) : uri.port;

    try {
      // Étape 1 : connexion TCP vers le proxy SOCKS5.
      final socket = await Socket.connect(_proxyHost, _proxyPort);

      // Étape 2 : handshake SOCKS5.
      await _socks5Connect(socket, targetHost, targetPort);

      // Étape 3 : envelopper dans TLS si nécessaire.
      Socket secureSocket;
      if (isSecure) {
        secureSocket = await SecureSocket.secure(
          socket,
          host: targetHost,
          onBadCertificate: (_) => true,
        );
      } else {
        secureSocket = socket;
      }

      // Étape 4 : construire et envoyer la requête HTTP.
      final httpRequest = _buildHttpRequest(request, uri);
      secureSocket.add(utf8.encode(httpRequest));

      // Si la requête a un body, l'envoyer.
      if (request is http.Request && request.body.isNotEmpty) {
        secureSocket.add(utf8.encode(request.body));
      }

      await secureSocket.flush();

      // Étape 5 : lire la réponse.
      final responseBytes = await secureSocket
          .timeout(const Duration(seconds: 30))
          .fold<BytesBuilder>(BytesBuilder(), (builder, data) {
        builder.add(data);
        return builder;
      });

      await secureSocket.close();

      final responseString = utf8.decode(responseBytes.toBytes());
      return _parseHttpResponse(responseString, request);
    } catch (e) {
      debugPrint('[TorHttpClient] Erreur: $e');
      return http.StreamedResponse(
        Stream.value(utf8.encode('Error: $e')),
        500,
      );
    }
  }

  /// Handshake SOCKS5 : auth none + CONNECT.
  Future<void> _socks5Connect(Socket socket, String host, int port) async {
    // Méthode d'auth : aucune (0x00).
    socket.add([0x05, 0x01, 0x00]);

    final methodResponse = await socket.first
        .timeout(const Duration(seconds: 10));

    if (methodResponse.length < 2 || methodResponse[1] != 0x00) {
      throw Exception(
          'SOCKS5: auth refusée (code ${methodResponse[1]})');
    }

    // Deuxième phase : demande de connexion.
    final hostBytes = Uint8List.fromList(utf8.encode(host));
    final request = BytesBuilder();
    request.add([0x05, 0x01, 0x00, 0x03]);
    request.addByte(hostBytes.length);
    request.add(hostBytes);
    request.addByte((port >> 8) & 0xFF);
    request.addByte(port & 0xFF);

    socket.add(request.toBytes());

    final connectResponse = await socket.first
        .timeout(const Duration(seconds: 10));

    if (connectResponse.length < 2 || connectResponse[1] != 0x00) {
      throw Exception(
          'SOCKS5: connexion vers $host:$port refusée (status ${connectResponse[1]})');
    }
  }

  /// Construit la requête HTTP à partir d'une BaseRequest.
  String _buildHttpRequest(http.BaseRequest request, Uri uri) {
    final buffer = StringBuffer();
    buffer.write('${request.method} ${uri.path} HTTP/1.1\r\n');
    buffer.write('Host: ${uri.host}\r\n');

    request.headers.forEach((key, value) {
      buffer.write('$key: $value\r\n');
    });

    if (request.contentLength != null && request.contentLength! > 0) {
      buffer.write('Content-Length: ${request.contentLength}\r\n');
    }

    buffer.write('Connection: close\r\n');
    buffer.write('\r\n');

    return buffer.toString();
  }

  /// Parse une réponse HTTP brute en StreamedResponse.
  http.StreamedResponse _parseHttpResponse(
    String raw,
    http.BaseRequest request,
  ) {
    final firstLineEnd = raw.indexOf('\r\n');
    if (firstLineEnd == -1) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(raw)),
        500,
      );
    }

    final statusLine = raw.substring(0, firstLineEnd);
    final parts = statusLine.split(' ');
    final statusCode = parts.length >= 2 ? int.tryParse(parts[1]) ?? 500 : 500;

    final headerEnd = raw.indexOf('\r\n\r\n');
    if (headerEnd == -1) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(raw)),
        statusCode,
      );
    }

    final headerSection = raw.substring(firstLineEnd + 2, headerEnd);
    final body = raw.substring(headerEnd + 4);

    final headers = <String, String>{};
    for (final line in headerSection.split('\r\n')) {
      final colonIndex = line.indexOf(':');
      if (colonIndex != -1) {
        final key = line.substring(0, colonIndex).trim();
        final value = line.substring(colonIndex + 1).trim();
        headers[key] = value;
      }
    }

    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      statusCode,
      headers: headers,
      contentLength: body.length,
      request: request,
    );
  }
}
