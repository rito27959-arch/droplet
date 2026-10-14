// Ce que l'interface sait des transferts, des appareils et des sessions —
// lu dans les événements JSON du moteur Rust.

enum EtatTransfert { enAttente, connexion, attenteReponse, transfert, interrompu, reprise, verification, termine, refuse, annule, echec }

EtatTransfert etatDe(String s) => switch (s) {
      'connexion' => EtatTransfert.connexion,
      'attente_reponse' => EtatTransfert.attenteReponse,
      'transfert' => EtatTransfert.transfert,
      'interrompu' => EtatTransfert.interrompu,
      'reprise' => EtatTransfert.reprise,
      'verification' => EtatTransfert.verification,
      'termine' => EtatTransfert.termine,
      'refuse' => EtatTransfert.refuse,
      'annule' => EtatTransfert.annule,
      'echec' => EtatTransfert.echec,
      _ => EtatTransfert.enAttente,
    };

extension EtatFinal on EtatTransfert {
  bool get finale => this == EtatTransfert.termine || this == EtatTransfert.refuse || this == EtatTransfert.annule || this == EtatTransfert.echec;
  bool get actif => this == EtatTransfert.transfert || this == EtatTransfert.reprise || this == EtatTransfert.verification;
}

class Pair {
  const Pair({required this.nom, required this.plateforme, required this.empreinte, required this.courte});

  final String nom;
  final String plateforme;
  final String empreinte;
  final String courte;

  factory Pair.json(Map<String, dynamic> j) => Pair(
        nom: j['nom'] as String? ?? '',
        plateforme: j['plateforme'] as String? ?? '',
        empreinte: j['empreinte'] as String? ?? '',
        courte: j['courte'] as String? ?? '',
      );
}

class Fichier {
  const Fichier(this.chemin, this.taille);

  final String chemin;
  final int taille;

  String get nom => chemin.split('/').last;

  static List<Fichier> liste(Object? l) => [
        for (final e in (l as List? ?? const []))
          if (e is List && e.length == 2) Fichier(e[0] as String, (e[1] as num).toInt()),
      ];
}

class Transfert {
  Transfert({
    required this.id,
    required this.groupe,
    required this.envoi,
    required this.pair,
    required this.etat,
    required this.octets,
    required this.total,
    required this.debit,
    required this.restant,
    required this.erreur,
    required this.chemins,
    required this.fichiers,
  });

  final String id;
  final String groupe;
  final bool envoi;
  final Pair pair;
  final EtatTransfert etat;
  final int octets;
  final int total;
  final int debit;
  final int? restant;
  final String? erreur;
  final List<String> chemins;
  final List<Fichier> fichiers;

  double get progression => total == 0 ? (etat == EtatTransfert.termine ? 1 : 0) : octets / total;

  factory Transfert.json(Map<String, dynamic> j) => Transfert(
        id: j['id'] as String,
        groupe: j['groupe'] as String? ?? '',
        envoi: j['sens'] == 'envoi',
        pair: Pair.json((j['pair'] as Map?)?.cast<String, dynamic>() ?? const {}),
        etat: etatDe(j['etat'] as String? ?? ''),
        octets: (j['octets'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        debit: (j['debit'] as num?)?.toInt() ?? 0,
        restant: (j['restant'] as num?)?.toInt(),
        erreur: j['erreur'] as String?,
        chemins: (j['chemins'] as List? ?? const []).cast<String>(),
        fichiers: Fichier.liste(j['fichiers']),
      );
}

class AppareilVu {
  const AppareilVu({required this.id, required this.nom, required this.plateforme, required this.empreinte, required this.adresses, this.distributions = const []});

  final String id;
  final String nom;
  final String plateforme;
  final String empreinte;
  final List<String> adresses;

  /// Les distributions Group Drop que cet appareil ouvre à ses voisins
  /// (les 8 premiers caractères de leur identifiant) : on les rejoint avec
  /// le code à six chiffres affiché sur son écran.
  final List<String> distributions;

  factory AppareilVu.json(Map<String, dynamic> j) => AppareilVu(
        id: j['id'] as String,
        nom: j['nom'] as String? ?? '',
        plateforme: j['plateforme'] as String? ?? '',
        empreinte: j['empreinte'] as String? ?? '',
        adresses: (j['adresses'] as List? ?? const []).cast<String>(),
        distributions: (j['distributions'] as List? ?? const []).cast<String>(),
      );

  Map<String, dynamic> cible() => {'adresses': adresses, 'empreinte': empreinte, 'nom': nom};

  String get courte => empreinte.length >= 8 ? '${empreinte.substring(0, 4)}-${empreinte.substring(4, 8)}'.toUpperCase() : '';
}

class Offre {
  const Offre({required this.id, required this.de, required this.fichiers, required this.total});

  final String id;
  final Pair de;
  final List<Fichier> fichiers;
  final int total;
}

class EtatSession {
  const EtatSession({required this.id, required this.etat, required this.participants, required this.termines});

  final String id;

  /// ouverte, en_cours, pause, terminee
  final String etat;
  final int participants;
  final int termines;
}

class Session {
  const Session({required this.id, required this.invitation, this.code = '', required this.expire, required this.total, required this.fichiers});

  final String id;
  final String invitation;

  /// Le code à six chiffres pour rejoindre depuis la liste « à proximité ».
  final String code;
  final DateTime expire;
  final int total;
  final List<Fichier> fichiers;

  factory Session.json(Map<String, dynamic> j) => Session(
        id: j['id'] as String,
        invitation: j['invitation'] as String,
        code: j['code'] as String? ?? '',
        expire: DateTime.fromMillisecondsSinceEpoch(((j['expire'] as num).toInt()) * 1000),
        total: (j['total'] as num).toInt(),
        fichiers: Fichier.liste(j['fichiers']),
      );
}

class EntreeHistorique {
  const EntreeHistorique({
    required this.id,
    required this.envoi,
    required this.titre,
    required this.fichiers,
    required this.taille,
    required this.appareil,
    required this.etat,
    required this.fin,
    required this.chemins,
  });

  final String id;
  final bool envoi;
  final String titre;
  final int fichiers;
  final int taille;
  final String appareil;
  final EtatTransfert etat;
  final DateTime fin;
  final List<String> chemins;

  factory EntreeHistorique.json(Map<String, dynamic> j) => EntreeHistorique(
        id: j['id'] as String,
        envoi: j['sens'] == 'envoi',
        titre: j['titre'] as String? ?? '',
        fichiers: (j['fichiers'] as num?)?.toInt() ?? 0,
        taille: (j['taille'] as num?)?.toInt() ?? 0,
        appareil: j['appareil'] as String? ?? '',
        etat: etatDe(j['etat'] as String? ?? ''),
        fin: DateTime.fromMillisecondsSinceEpoch(((j['fin'] as num?)?.toInt() ?? 0) * 1000),
        chemins: (j['chemins'] as String? ?? '').split('\n').where((x) => x.isNotEmpty).toList(),
      );
}

/// Un fichier choisi pour l'envoi : où il est, le nom qu'il aura chez
/// l'autre (avec ses dossiers), sa taille.
class Choisi {
  const Choisi({required this.chemin, required this.nom, required this.taille});

  final String chemin;
  final String nom;
  final int taille;
}
