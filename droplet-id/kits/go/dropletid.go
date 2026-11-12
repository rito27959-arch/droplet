// Package dropletid : se connecter avec Droplet ID depuis un serveur Go,
// par-dessus coreos/go-oidc et golang.org/x/oauth2 (bibliothèques standard
// de l'écosystème).
//
//	did, _ := dropletid.Nouveau(ctx, dropletid.Options{ClientID: "mon-site", RedirectURI: "https://mon-site.cm/connexion/retour"})
//	url, attente := did.Commencer()          // garder `attente` en session
//	session, err := did.Terminer(ctx, r.URL.Query(), attente)
//	session.Sub                               // identifiant propre à votre site
package dropletid

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"net/url"

	"github.com/coreos/go-oidc/v3/oidc"
	"golang.org/x/oauth2"
)

const (
	Emetteur     = "https://id.dropletmesh.app"
	EmetteurTest = "https://id-test.dropletmesh.app"
)

type Options struct {
	ClientID     string
	ClientSecret string // vide pour un client public (PKCE seul)
	RedirectURI  string
	Emetteur     string   // Emetteur par défaut
	Portees      []string // ["openid"] par défaut ; ajouter "profile" pour le pseudo
}

// Attente : à garder côté serveur entre Commencer et Terminer.
type Attente struct {
	Verifier string `json:"verifier"`
	State    string `json:"state"`
	Nonce    string `json:"nonce"`
}

type Session struct {
	Sub          string
	Pseudo       string
	IDToken      string
	AccessToken  string
	RefreshToken string
}

type DropletID struct {
	conf     oauth2.Config
	verif    *oidc.IDTokenVerifier
	provider *oidc.Provider
	profil   bool
}

func Nouveau(ctx context.Context, o Options) (*DropletID, error) {
	if o.Emetteur == "" {
		o.Emetteur = Emetteur
	}
	portees := o.Portees
	if len(portees) == 0 {
		portees = []string{oidc.ScopeOpenID}
	}
	p, err := oidc.NewProvider(ctx, o.Emetteur)
	if err != nil {
		return nil, err
	}
	profil := false
	for _, s := range portees {
		profil = profil || s == "profile"
	}
	return &DropletID{
		conf: oauth2.Config{ClientID: o.ClientID, ClientSecret: o.ClientSecret, RedirectURL: o.RedirectURI, Endpoint: p.Endpoint(), Scopes: portees},
		verif:    p.Verifier(&oidc.Config{ClientID: o.ClientID, SupportedSigningAlgs: []string{oidc.ES256}}),
		provider: p,
		profil:   profil,
	}, nil
}

func aleatoire() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}

// Commencer rend l'adresse de Droplet ID et l'attente à garder.
func (d *DropletID) Commencer() (string, Attente) {
	a := Attente{Verifier: oauth2.GenerateVerifier(), State: aleatoire(), Nonce: aleatoire()}
	u := d.conf.AuthCodeURL(a.State, oauth2.S256ChallengeOption(a.Verifier), oidc.Nonce(a.Nonce))
	return u, a
}

var ErrState = errors.New("droplet-id: réponse inattendue (state)")

// Terminer vérifie la réponse (state, PKCE, ID token) et rend la session.
func (d *DropletID) Terminer(ctx context.Context, q url.Values, a Attente) (*Session, error) {
	if e := q.Get("error"); e != "" {
		return nil, errors.New("droplet-id: " + e + " " + q.Get("error_description"))
	}
	if q.Get("state") == "" || q.Get("state") != a.State {
		return nil, ErrState
	}
	t, err := d.conf.Exchange(ctx, q.Get("code"), oauth2.VerifierOption(a.Verifier))
	if err != nil {
		return nil, err
	}
	brut, _ := t.Extra("id_token").(string)
	idt, err := d.verif.Verify(ctx, brut)
	if err != nil {
		return nil, err
	}
	if idt.Nonce != a.Nonce {
		return nil, errors.New("droplet-id: nonce")
	}
	s := &Session{Sub: idt.Subject, IDToken: brut, AccessToken: t.AccessToken, RefreshToken: t.RefreshToken}
	if d.profil {
		info, err := d.provider.UserInfo(ctx, oauth2.StaticTokenSource(t))
		if err == nil && info.Subject == idt.Subject {
			var c struct {
				Pseudo string `json:"preferred_username"`
			}
			_ = info.Claims(&c)
			s.Pseudo = c.Pseudo
		}
	}
	return s, nil
}
