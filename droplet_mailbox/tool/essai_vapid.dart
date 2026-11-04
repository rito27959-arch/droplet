// Vérification hors serveur de la signature VAPID (lancée par la CI) :
// fabrique une clé, signe un jeton, et l'imprime avec la clé publique pour
// qu'un outil indépendant vérifie la signature ES256.
import 'package:droplet_mailbox/push_web.dart';

void main() {
  final essai = PushWeb.essai();
  print('VAPID_CLE ${essai.$1}');
  print('VAPID_JETON ${essai.$2}');
  print('ADRESSE_FCM ${adressePushAcceptable('https://fcm.googleapis.com/fcm/send/abc')}');
  print('ADRESSE_AUTRE ${adressePushAcceptable('https://exemple.com/x')}');
}
