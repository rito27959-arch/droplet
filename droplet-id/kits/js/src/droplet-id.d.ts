export declare const EMETTEUR: 'https://id.dropletmesh.app';
export declare const EMETTEUR_TEST: 'https://id-test.dropletmesh.app';
export declare const GOUTTE_SVG: string;
export declare const STYLE_BOUTON: string;

export interface OptionsDropletId {
  /** Identifiant du site, donné à l'enregistrement. */
  clientId: string;
  /** Adresse de retour, exactement celle enregistrée. */
  redirectUri: string;
  /** Par défaut https://id.dropletmesh.app. */
  emetteur?: string;
  /** ['openid'] par défaut ; ajouter 'profile' pour recevoir le pseudo choisi. */
  portees?: Array<'openid' | 'profile' | 'offline_access'>;
  langue?: 'fr' | 'en';
}

export interface SessionDropletId {
  /** Identifiant de la personne, propre à VOTRE site. Stable. */
  sub: string;
  /** Pseudo choisi pour votre site (portée `profile`), ou null. */
  pseudo: string | null;
  idToken: string;
  accessToken: string;
  /** Millisecondes depuis 1970. */
  expireLe: number;
}

export declare class ErreurDropletId extends Error {
  code: string;
}

export declare class DropletId {
  constructor(options: OptionsDropletId);
  connecter(): Promise<void>;
  urlDeConnexion(): Promise<string>;
  estUnRetour(url?: string): boolean;
  terminerConnexion(url?: string): Promise<SessionDropletId>;
  verifierIdToken(jwt: string, nonce?: string): Promise<Record<string, unknown>>;
  utilisateur(): { sub: string; pseudo: string | null } | null;
  deconnecter(options?: { partout?: boolean; retour?: string }): Promise<void>;
}

export declare function boutonDropletId(options?: {
  langue?: 'fr' | 'en';
  variante?: 'sombre' | 'clair' | 'bleu';
  taille?: 'petit' | 'moyen' | 'grand';
  pleineLargeur?: boolean;
  onClick?: (e: MouseEvent) => unknown;
}): HTMLButtonElement;
