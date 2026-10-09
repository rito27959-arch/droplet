// LES DISCUSSIONS D'EXEMPLE — pour voir l'interface avant que la liaison
// fonctionne (adresse ?apercu). Rien n'y est envoyé ni reçu.
//
// Le jour où le navigateur reçoit ses vraies discussions, l'interface lit
// la même forme de données : `Discussion` et `MessageApercu` deviennent les
// modèles de la boîte aux lettres, sans toucher aux écrans.
import 'package:flutter/widgets.dart';

class MessageApercu {
  const MessageApercu(this.texte, {required this.deMoi, required this.heure, this.lu = true});

  final String texte;
  final bool deMoi;
  final String heure;
  final bool lu;
}

class Discussion {
  const Discussion({
    required this.nom,
    required this.couleurs,
    required this.apercu,
    required this.heure,
    this.nonLus = 0,
    this.groupe = false,
    this.epingle = false,
    this.enLigne = false,
    this.messages = const [],
  });

  final String nom;
  final List<Color> couleurs;
  final String apercu;
  final String heure;
  final int nonLus;
  final bool groupe;
  final bool epingle;
  final bool enLigne;
  final List<MessageApercu> messages;

  String get initiale => nom.isEmpty ? '?' : nom.characters.first.toUpperCase();
}

/// Les discussions d'exemple, en français ou en anglais selon la langue.
List<Discussion> discussionsApercu(String langue) =>
    langue == 'fr' ? _fr : _en;

const _rose = [Color(0xFFFF9F0A), Color(0xFFFF375F)];
const _bleu = [Color(0xFF64D2FF), Color(0xFF0A84FF)];
const _violet = [Color(0xFFDA8FFF), Color(0xFF8E4DFF)];
const _vert = [Color(0xFF63E6BE), Color(0xFF30B0C7)];
const _orange = [Color(0xFFFFD60A), Color(0xFFFF9F0A)];

const _fr = <Discussion>[
  Discussion(
    nom: 'Amina',
    couleurs: _rose,
    apercu: 'Je te vois, j’arrive !',
    heure: '21:04',
    nonLus: 2,
    epingle: true,
    enLigne: true,
    messages: [
      MessageApercu('Tu es où ? Plus aucun réseau ici 😅', deMoi: false, heure: '21:02'),
      MessageApercu('Devant la grande scène. Tout est coupé, même la 4G', deMoi: true, heure: '21:03'),
      MessageApercu('Ton message est passé par deux téléphones avant de m’arriver 🤯', deMoi: false, heure: '21:03'),
      MessageApercu('C’est tout l’intérêt de Droplet', deMoi: true, heure: '21:04'),
      MessageApercu('Je te vois, j’arrive !', deMoi: false, heure: '21:04'),
    ],
  ),
  Discussion(
    nom: 'Famille',
    couleurs: _vert,
    apercu: 'Papa : On se retrouve chez mamie à 18 h',
    heure: '20:31',
    groupe: true,
    messages: [
      MessageApercu('Qui ramène le pain ?', deMoi: false, heure: '20:12'),
      MessageApercu('Moi, je passe à la boulangerie', deMoi: true, heure: '20:14'),
      MessageApercu('On se retrouve chez mamie à 18 h', deMoi: false, heure: '20:31'),
    ],
  ),
  Discussion(
    nom: 'Papa',
    couleurs: _bleu,
    apercu: 'Bien reçu, merci 🙏',
    heure: '19:47',
    messages: [
      MessageApercu('Tu as pu recharger ton téléphone ?', deMoi: false, heure: '19:40'),
      MessageApercu('Oui, à 80 %. Je garde Droplet ouvert', deMoi: true, heure: '19:45'),
      MessageApercu('Bien reçu, merci 🙏', deMoi: false, heure: '19:47'),
    ],
  ),
  Discussion(
    nom: 'Lina',
    couleurs: _violet,
    apercu: 'Message vocal (0:27)',
    heure: 'Hier',
    nonLus: 1,
  ),
  Discussion(
    nom: 'Club de randonnée',
    couleurs: _orange,
    apercu: 'Karim : Départ 7 h au parking du col',
    heure: 'Mardi',
    groupe: true,
  ),
];

const _en = <Discussion>[
  Discussion(
    nom: 'Amina',
    couleurs: _rose,
    apercu: 'I can see you, coming!',
    heure: '21:04',
    nonLus: 2,
    epingle: true,
    enLigne: true,
    messages: [
      MessageApercu('Where are you? No signal at all here 😅', deMoi: false, heure: '21:02'),
      MessageApercu('In front of the main stage. Everything is down, even 4G', deMoi: true, heure: '21:03'),
      MessageApercu('Your message hopped through two phones to reach me 🤯', deMoi: false, heure: '21:03'),
      MessageApercu('That’s the whole point of Droplet', deMoi: true, heure: '21:04'),
      MessageApercu('I can see you, coming!', deMoi: false, heure: '21:04'),
    ],
  ),
  Discussion(
    nom: 'Family',
    couleurs: _vert,
    apercu: 'Dad: Let’s meet at grandma’s at 6 pm',
    heure: '20:31',
    groupe: true,
    messages: [
      MessageApercu('Who’s bringing bread?', deMoi: false, heure: '20:12'),
      MessageApercu('Me, I’ll stop by the bakery', deMoi: true, heure: '20:14'),
      MessageApercu('Let’s meet at grandma’s at 6 pm', deMoi: false, heure: '20:31'),
    ],
  ),
  Discussion(
    nom: 'Dad',
    couleurs: _bleu,
    apercu: 'Got it, thanks 🙏',
    heure: '19:47',
    messages: [
      MessageApercu('Did you manage to charge your phone?', deMoi: false, heure: '19:40'),
      MessageApercu('Yes, 80%. Keeping Droplet open', deMoi: true, heure: '19:45'),
      MessageApercu('Got it, thanks 🙏', deMoi: false, heure: '19:47'),
    ],
  ),
  Discussion(
    nom: 'Lina',
    couleurs: _violet,
    apercu: 'Voice message (0:27)',
    heure: 'Yesterday',
    nonLus: 1,
  ),
  Discussion(
    nom: 'Hiking club',
    couleurs: _orange,
    apercu: 'Karim: Leaving at 7 am from the pass car park',
    heure: 'Tuesday',
    groupe: true,
  ),
];
