import 'package:flutter_test/flutter_test.dart';
import 'package:droplet/core/models/mesh_message.dart';
import 'package:droplet/core/services/storage_service.dart';

void main() {
  group('MeshStatusRecord.isExpired', () {
    test('non expiré tant que expiresAt est dans le futur', () {
      final status = MeshStatusRecord(
        id: 's1', authorId: 'a', authorPseudo: 'Alice', content: 'Salut',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(status.isExpired, isFalse);
    });

    test('expiré une fois expiresAt dépassé', () {
      final status = MeshStatusRecord(
        id: 's2', authorId: 'a', authorPseudo: 'Alice', content: 'Salut',
        createdAt: DateTime.now().subtract(const Duration(hours: 25)),
        expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(status.isExpired, isTrue);
    });
  });

  group('StorageService.getActiveStatuses (mode cache mémoire, sans DB)', () {
    test('exclut les statuts expirés de la lecture', () async {
      final active = MeshStatusRecord(
        id: 'active-1', authorId: 'alice', authorPseudo: 'Alice', content: 'Encore visible',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final expired = MeshStatusRecord(
        id: 'expired-1', authorId: 'bob', authorPseudo: 'Bob', content: 'Plus visible',
        createdAt: DateTime.now().subtract(const Duration(hours: 25)),
        expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      await StorageService.saveStatus(active);
      await StorageService.saveStatus(expired);

      final visible = StorageService.getActiveStatuses();
      expect(visible.any((s) => s.id == 'active-1'), isTrue);
      expect(visible.any((s) => s.id == 'expired-1'), isFalse);
    });

    test('trie du plus récent au plus ancien', () async {
      final older = MeshStatusRecord(
        id: 'older', authorId: 'carol', authorPseudo: 'Carol', content: 'Plus vieux',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        expiresAt: DateTime.now().add(const Duration(hours: 22)),
      );
      final newer = MeshStatusRecord(
        id: 'newer', authorId: 'carol', authorPseudo: 'Carol', content: 'Plus récent',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      );

      await StorageService.saveStatus(older);
      await StorageService.saveStatus(newer);

      final visible = StorageService.getActiveStatuses();
      final indexNewer = visible.indexWhere((s) => s.id == 'newer');
      final indexOlder = visible.indexWhere((s) => s.id == 'older');
      expect(indexNewer, lessThan(indexOlder));
    });
  });
}
