import 'dart:convert';

import 'package:shelf/shelf.dart';

/// An invitation exists only for one minute, starting when the browser reserves it.
/// State is process local: use a shared store before running multiple replicas.
class LiaisonStore {
  LiaisonStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Map<String, _Invitation> _invitations = {};
  static const lifetime = Duration(minutes: 1);
  static const maxPending = 2048;

  void sweep() => _invitations.removeWhere((_, invitation) =>
      !_clock().isBefore(invitation.expiresAt));

  bool reserve(String channel) {
    sweep();
    if (_invitations.containsKey(channel) || _invitations.length >= maxPending) {
      return false;
    }
    _invitations[channel] = _Invitation(_clock().add(lifetime));
    return true;
  }

  bool get existsCapacity => _invitations.length < maxPending;

  int publish(String channel, Map<String, dynamic> envelope) {
    sweep();
    final invitation = _invitations[channel];
    if (invitation == null) return 404;
    if (invitation.envelope != null) return 409;
    invitation.envelope = envelope;
    return 200;
  }

  Map<String, dynamic>? read(String channel) {
    sweep();
    return _invitations[channel]?.envelope;
  }

  bool contains(String channel) {
    sweep();
    return _invitations.containsKey(channel);
  }
}

class _Invitation {
  _Invitation(this.expiresAt);
  final DateTime expiresAt;
  Map<String, dynamic>? envelope;
}

final liaisonStore = LiaisonStore();
final _channelPattern = RegExp(r'^[A-Za-z0-9_-]{22}$');
final _base64Pattern = RegExp(r'^[A-Za-z0-9_-]+={0,2}$');

bool _base64Sized(Object? value, int length) {
  if (value is! String || !_base64Pattern.hasMatch(value)) return false;
  try {
    return base64Url.decode(base64Url.normalize(value)).length == length;
  } on FormatException {
    return false;
  }
}

bool _validChannel(String channel) =>
    _channelPattern.hasMatch(channel) && _base64Sized(channel, 16);

Response _json(int status, Map<String, dynamic> data) => Response(
      status,
      body: jsonEncode(data),
      headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
    );

Response reserveLiaison(Request request, String channel) {
  if (!_validChannel(channel)) return _json(400, {'error': 'canal invalide'});
  if (!liaisonStore.existsCapacity) liaisonStore.sweep();
  if (!liaisonStore.existsCapacity) return _json(503, {'error': 'capacité atteinte'});
  if (!liaisonStore.reserve(channel)) return _json(409, {'error': 'canal déjà réservé'});
  return _json(201, {'ok': true, 'expiresIn': 60});
}

Future<Response> publishLiaison(Request request, String channel) async {
  if (!_validChannel(channel)) return _json(400, {'error': 'canal invalide'});
  if (!liaisonStore.contains(channel)) return _json(404, {'error': 'canal expiré ou absent'});
  try {
    final bytes = await request.read().fold<List<int>>(<int>[], (result, chunk) {
      if (result.length + chunk.length > 4096) throw const FormatException('trop volumineux');
      return result..addAll(chunk);
    });
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic> || value['v'] != 1 ||
        !_base64Sized(value['cleTel'], 32) || !_base64Sized(value['nonce'], 12) ||
        value['chiffre'] is! String ||
        !_base64Pattern.hasMatch(value['chiffre'] as String) ||
        (value['chiffre'] as String).length > 3000 ||
        !_base64AtLeast(value['chiffre'], 17)) {
      return _json(400, {'error': 'enveloppe invalide'});
    }
    final status = liaisonStore.publish(channel, {
      'v': 1,
      'cleTel': value['cleTel'] as String,
      'nonce': value['nonce'] as String,
      'chiffre': value['chiffre'] as String,
    });
    return _json(status, status == 200 ? {'ok': true} : {'error': 'canal expiré ou déjà utilisé'});
  } on FormatException {
    return _json(400, {'error': 'requête invalide'});
  } catch (_) {
    return _json(400, {'error': 'requête invalide'});
  }
}

bool _base64AtLeast(Object? value, int length) {
  try {
    return value is String &&
        base64Url.decode(base64Url.normalize(value)).length >= length;
  } on FormatException {
    return false;
  }
}

Response readLiaison(Request request, String channel) {
  if (!_validChannel(channel)) return _json(400, {'error': 'canal invalide'});
  if (!liaisonStore.contains(channel)) return _json(404, {'error': 'canal expiré ou absent'});
  final envelope = liaisonStore.read(channel);
  if (envelope == null) return Response(204, headers: {'cache-control': 'no-store'});
  // The ciphertext can be read again during the minute: a third party cannot
  // consume and erase the message before the browser decrypts it.
  return _json(200, envelope);
}

Middleware liaisonCors({String? allowedOrigin}) {
  final origin = allowedOrigin ?? 'https://web.dropletmesh.app';
  return (inner) => (request) async {
        if (!request.url.path.startsWith('liaison/')) return inner(request);
        final requestOrigin = request.headers['origin'];
        if (requestOrigin != null && requestOrigin != origin) {
          return _json(403, {'error': 'origine interdite'});
        }
        final headers = {
          'access-control-allow-origin': origin,
          'access-control-allow-methods': 'GET, PUT, OPTIONS',
          'access-control-allow-headers': 'content-type',
          'vary': 'Origin',
          'cache-control': 'no-store',
        };
        if (request.method == 'OPTIONS') return Response(204, headers: headers);
        final response = await inner(request);
        return response.change(headers: {...response.headers, ...headers});
      };
}
