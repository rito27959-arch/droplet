import 'package:droplet/features/droplet_id/droplet_id_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reconnaît un lien de demande Droplet ID, et rien d’autre', () {
    expect(DropletIdService.demandeDepuis('https://id-test.dropletmesh.app/a/AbCdEfGhIjKlMnOpQrSt12'), 'AbCdEfGhIjKlMnOpQrSt12');
    expect(DropletIdService.demandeDepuis('https://id.dropletmesh.app/a/AbCdEfGhIjKlMnOpQrSt12'), 'AbCdEfGhIjKlMnOpQrSt12');
    expect(DropletIdService.demandeDepuis('http://id.dropletmesh.app/a/AbCdEfGhIjKlMnOpQrSt12'), isNull);
    expect(DropletIdService.demandeDepuis('https://pirate.example/a/AbCdEfGhIjKlMnOpQrSt12'), isNull);
    expect(DropletIdService.demandeDepuis('https://id.dropletmesh.app/a/court'), isNull);
    expect(DropletIdService.demandeDepuis('droplet:pair:xyz'), isNull);
    expect(DropletIdService.lienDepuis('https://id-test.dropletmesh.app/a/AbCdEfGhIjKlMnOpQrSt12')?.emetteur, emetteurDropletIdTest);
    expect(DropletIdService.lienDepuis('https://id.dropletmesh.app/a/AbCdEfGhIjKlMnOpQrSt12')?.emetteur, emetteurDropletId);
    expect(DropletIdService.pourHote('id-test.dropletmesh.app').estTest, isTrue);
    expect(DropletIdService.pourHote(null).estTest, isFalse);
    expect(DropletIdService.pourHote('pirate.example').emetteur, emetteurDropletId);
  });
}
