import type { ReactNode, ButtonHTMLAttributes } from 'react';
import type { DropletId, OptionsDropletId } from '@droplet/id';

export interface UtilisateurDropletId {
  /** Identifiant propre à votre site, stable. */
  sub: string;
  pseudo: string | null;
}

export declare function DropletIdProvider(props: OptionsDropletId & { children?: ReactNode }): JSX.Element;

export declare function useDropletId(): {
  utilisateur: UtilisateurDropletId | null;
  /** Vrai pendant le retour de Droplet ID (échange du code). */
  chargement: boolean;
  erreur: (Error & { code?: string }) | null;
  connecter(): Promise<void>;
  deconnecter(options?: { partout?: boolean; retour?: string }): Promise<void>;
  client: DropletId;
};

export declare function DropletIdButton(
  props: {
    langue?: 'fr' | 'en';
    variante?: 'sombre' | 'clair' | 'bleu';
    taille?: 'petit' | 'moyen' | 'grand';
    pleineLargeur?: boolean;
    children?: ReactNode;
  } & Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'onClick' | 'type'>,
): JSX.Element;
