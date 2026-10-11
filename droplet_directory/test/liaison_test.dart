import 'dart:convert';

import 'package:droplet_directory/liaison.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final channel = base64Url.encode(List<int>.generate(16, (i) => i)).replaceAll('=', '');
  final envelope = {
    'v': 1,
    'cleTel': base64Url.encode(List<int>.filled(32, 7)).replaceAll('=', ''),
    'nonce': base64Url.encode(List<int>.filled(12, 8)).replaceAll('=', ''),
    'chiffre': base64Url.encode(List<int>.filled(32, 9)).replaceAll('=', ''),
  };
  final url = Uri.parse('http://localhost/liaison/$channel');

  test('reserve, poll, publish once and read encrypted data', () async {
    expect((await reserveLiaison(Request('PUT', url), channel)).statusCode, 201);
    expect(readLiaison(Request('GET', url), channel).statusCode, 204);
    expect((await publishLiaison(Request('POST', url, body: jsonEncode(envelope)), channel)).statusCode, 200);
    final response = readLiaison(Request('GET', url), channel);
    expect(response.statusCode, 200);
    expect(jsonDecode(await response.readAsString()), envelope);
    expect((await publishLiaison(Request('POST', url, body: jsonEncode(envelope)), channel)).statusCode, 409);
  });

  test('channel expires based on reservation time', () {
    var now = DateTime.utc(2026, 1, 1);
    final store = LiaisonStore(clock: () => now);
    expect(store.reserve(channel), true);
    now = now.add(const Duration(seconds: 61));
    expect(store.contains(channel), false);
    expect(store.publish(channel, envelope), 404);
  });

  test('CORS only permits configured web origin', () async {
    final handler = liaisonCors()((request) => readLiaison(request, channel));
    final allowed = await handler(Request('OPTIONS', url, headers: {'origin': 'https://web.dropletmesh.app'}));
    expect(allowed.statusCode, 204);
    expect(allowed.headers['access-control-allow-origin'], 'https://web.dropletmesh.app');
    final rejected = await handler(Request('OPTIONS', url, headers: {'origin': 'https://other.example'}));
    expect(rejected.statusCode, 403);
  });
}
