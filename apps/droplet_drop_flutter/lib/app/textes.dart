// Les textes de l'application, dans les dix langues de Droplet.
// `context.t('cle')`, avec des paramètres : `context.t('cle', {'n': '3'})`.
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

import 'etat_app.dart';
import 'textes_langues.dart';

export 'textes_langues.dart' show textes;

const langues = {
  'fr': 'Français',
  'en': 'English',
  'es': 'Español',
  'de': 'Deutsch',
  'it': 'Italiano',
  'pt': 'Português',
  'ru': 'Русский',
  'ar': 'العربية',
  'hi': 'हिन्दी',
  'zh': '中文',
};

String langueCourante() {
  final choisie = EtatApp.i.langue;
  if (choisie != null && textes.containsKey(choisie)) return choisie;
  final sys = PlatformDispatcher.instance.locale.languageCode;
  return textes.containsKey(sys) ? sys : 'en';
}

String tr(String cle, [Map<String, String> params = const {}]) {
  final l = langueCourante();
  var s = textes[l]?[cle] ?? textes['en']?[cle] ?? textes['fr']?[cle] ?? cle;
  params.forEach((k, v) => s = s.replaceAll('{$k}', v));
  return s;
}

extension Traduire on BuildContext {
  String t(String cle, [Map<String, String> params = const {}]) => tr(cle, params);
}

/// La taille d'un fichier dans les unités de la langue.
String tailleLocale(int octets) {
  final l = langueCourante();
  final fr = l == 'fr';
  final unites = fr ? ['o', 'Ko', 'Mo', 'Go', 'To'] : ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = octets.toDouble();
  var u = 0;
  while (v >= 1000 && u < unites.length - 1) {
    v /= 1000;
    u++;
  }
  final t = u == 0 || v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  final virgule = const {'fr', 'es', 'de', 'it', 'pt', 'ru'}.contains(l);
  return '${virgule ? t.replaceAll('.', ',') : t} ${unites[u]}';
}

String debitLocal(int octetsParSeconde) => '${tailleLocale(octetsParSeconde)}/s';

/// « 2 min 10 s », « 45 s », « 1 h 05 ».
String dureeLocale(int secondes) {
  if (secondes < 60) return tr('duree_s', {'s': '$secondes'});
  if (secondes < 3600) return tr('duree_min', {'m': '${secondes ~/ 60}', 's': '${secondes % 60}'});
  return tr('duree_h', {'h': '${secondes ~/ 3600}', 'm': '${(secondes % 3600 ~/ 60).toString().padLeft(2, '0')}'});
}

bool get rtl => langueCourante() == 'ar';

/// Pour le constructeur de MaterialApp.
Locale localeCourante() => Locale(langueCourante());
