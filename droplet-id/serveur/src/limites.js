// Un limiteur simple par adresse (fenêtre d'une minute), en mémoire.
// Suffisant pour un seul processus ; à remplacer par Postgres/Redis si l'on
// passe à plusieurs répliques.
export function limiteur({ parMinute }) {
  const compteurs = new Map();
  setInterval(() => compteurs.clear(), 60_000).unref();
  return (cle) => {
    const n = (compteurs.get(cle) ?? 0) + 1;
    compteurs.set(cle, n);
    return n <= parMinute;
  };
}
