// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// COMMENT ON NOMME QUELQU'UN, PARTOUT DANS L'APPLICATION.
//
// ── ⚠️ UN IDENTIFIANT N'EST PAS UN NOM, ET NE DOIT JAMAIS S'AFFICHER ──
//
// L'identité d'un pair est une empreinte de clé publique : soixante-
// quatre caractères hexadécimaux. Affichée telle quelle, elle ne dit
// rien, ne se retient pas, ne se distingue pas de la suivante — et
// aucune grande application ne montrerait ça à la place d'un nom.
//
// Le problème est qu'il n'y a pas toujours de nom. Sur un maillage, on
// croise des appareils dont on n'a jamais reçu le pseudonyme : le
// message est arrivé par relais, la fiche du pair n'existe pas encore,
// ou elle a été écrite avant l'échange de clés. Le repli était alors
// l'identifiant brut, à trois endroits différents et avec trois
// comportements différents.
//
// ── ⚠️ ET CERTAINES FICHES CONTIENNENT UN FAUX NOM ────────────────────
//
// D'anciennes versions fabriquaient un pseudonyme à partir de
// l'identifiant faute de mieux (voir `_vraiPseudo` côté transport, qui
// a fermé la porte à la source). Ces fiches existent déjà sur les
// appareils, avec une empreinte enregistrée EN GUISE DE NOM — et rien
// ne les corrigera tant que le pair ne repassera pas à portée.
//
// Un simple « le nom est-il nul ? » ne suffit donc pas : il faut
// vérifier que ce qu'on tient est vraiment un nom.
//
// ── Ce que ce fichier garantit ────────────────────────────────────────
//
// Une seule règle, un seul endroit, le même résultat sur tous les
// écrans : soit un vrai pseudonyme, soit « Pair 3f7a1c92 » — court,
// stable, et qui dit honnêtement qu'on ne connaît pas encore cette
// personne.
// ============================================================================

/// Le pseudonyme s'il en est vraiment un, `null` sinon.
///
/// Écarte le vide, les espaces seuls, et l'identifiant déguisé en nom.
String? pseudoValide(String? pseudo, String peerId) {
  if (pseudo == null) return null;
  final net = pseudo.trim();
  if (net.isEmpty) return null;
  if (net.toLowerCase() == peerId.toLowerCase()) return null;
  return net;
}

/// De quoi désigner un pair dont on n'a jamais appris le nom.
///
/// Huit caractères : assez pour distinguer deux contacts à l'œil, assez
/// peu pour tenir dans une barre de titre. L'empreinte entière ne
/// distinguait rien du tout, puisque l'œil n'en lit que le début.
String identifiantAbrege(String peerId) =>
    peerId.length <= 8 ? peerId : 'Pair ${peerId.substring(0, 8)}';

/// Le nom à afficher pour ce pair.
///
/// [propositions] sont essayées dans l'ordre — pseudonyme vivant, fiche
/// enregistrée, auteur d'un message reçu… La première qui est un vrai
/// nom gagne. Si aucune ne l'est, on abrège l'identifiant.
///
/// N'utilisez pas ce résultat comme clé : c'est un libellé destiné à
/// l'œil, et deux personnes peuvent parfaitement choisir le même.
String nomDuPair(String peerId, List<String?> propositions) {
  for (final p in propositions) {
    final v = pseudoValide(p, peerId);
    if (v != null) return v;
  }
  return identifiantAbrege(peerId);
}
