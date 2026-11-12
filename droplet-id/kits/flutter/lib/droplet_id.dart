/// Se connecter avec Droplet ID depuis une app Flutter.
///
/// ```dart
/// final did = DropletId(clientId: 'mon-app', redirectUri: 'cm.monapp:/connexion');
/// final session = await did.connecter();   // ouvre Droplet ID, revient
/// session.sub;                              // identifiant propre à votre app
/// ```
///
/// Et le bouton officiel : `DropletIdBouton(onPressed: ...)`.
library droplet_id;

export 'src/client.dart';
export 'src/bouton.dart';
