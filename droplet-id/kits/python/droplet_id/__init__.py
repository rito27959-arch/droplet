"""
droplet-id — se connecter avec Droplet ID depuis un site Python.

    from droplet_id import DropletId

    did = DropletId(client_id="mon-site", redirect_uri="https://mon-site.cm/connexion/retour")
    url, attente = did.commencer()           # garder `attente` en session
    session = did.terminer(url_de_retour, attente)
    session["sub"]                            # identifiant propre à votre site

Standard OpenID Connect : code + PKCE (S256), state, nonce ; l'ID token est
vérifié (signature ES256 via JWKS, émetteur, audience, dates, nonce).
Dépendance unique : `cryptography`.

Avec Flask : voir `droplet_id.flask.blueprint()`.
"""

from __future__ import annotations

import base64
import hashlib
import json
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature

__all__ = ["DropletId", "ErreurDropletId", "EMETTEUR", "EMETTEUR_TEST"]
__version__ = "0.1.0"

EMETTEUR = "https://id.dropletmesh.app"
EMETTEUR_TEST = "https://id-test.dropletmesh.app"


class ErreurDropletId(Exception):
    def __init__(self, code: str, description: str = ""):
        super().__init__(f"{code}: {description}" if description else code)
        self.code = code
        self.description = description


def _b64url(octets: bytes) -> str:
    return base64.urlsafe_b64encode(octets).rstrip(b"=").decode()


def _de_b64url(texte: str) -> bytes:
    return base64.urlsafe_b64decode(texte + "=" * (-len(texte) % 4))


def _json(url: str, donnees: dict | None = None, entetes: dict | None = None) -> dict:
    corps = urllib.parse.urlencode(donnees).encode() if donnees is not None else None
    req = urllib.request.Request(url, data=corps, headers={"accept": "application/json", **(entetes or {})})
    if corps is not None:
        req.add_header("content-type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            err = json.loads(e.read())
        except Exception:
            err = {}
        raise ErreurDropletId(err.get("error", f"http_{e.code}"), err.get("error_description", "")) from None


class DropletId:
    def __init__(
        self,
        client_id: str,
        redirect_uri: str,
        *,
        client_secret: str | None = None,
        emetteur: str = EMETTEUR,
        portees: list[str] | None = None,
    ):
        self.client_id = client_id
        self.redirect_uri = redirect_uri
        self.client_secret = client_secret
        self.emetteur = emetteur.rstrip("/")
        p = portees or ["openid"]
        self.portees = p if "openid" in p else ["openid", *p]
        self._config: dict | None = None
        self._cles: dict | None = None

    # ── Découverte ────────────────────────────────────────────────────
    def configuration(self) -> dict:
        if self._config is None:
            c = _json(f"{self.emetteur}/.well-known/openid-configuration")
            if c.get("issuer") != self.emetteur:
                raise ErreurDropletId("decouverte", "émetteur inattendu")
            self._config = c
        return self._config

    def _cle(self, kid: str | None) -> ec.EllipticCurvePublicKey:
        if self._cles is None or (kid and kid not in self._cles):
            jwks = _json(self.configuration()["jwks_uri"])
            self._cles = {}
            for k in jwks["keys"]:
                if k.get("kty") == "EC" and k.get("crv") == "P-256":
                    x = int.from_bytes(_de_b64url(k["x"]), "big")
                    y = int.from_bytes(_de_b64url(k["y"]), "big")
                    self._cles[k.get("kid")] = ec.EllipticCurvePublicNumbers(x, y, ec.SECP256R1()).public_key()
        if kid in self._cles:
            return self._cles[kid]
        if self._cles:
            return next(iter(self._cles.values()))
        raise ErreurDropletId("id_token", "aucune clé")

    # ── Connexion ─────────────────────────────────────────────────────
    def commencer(self, langue: str | None = None) -> tuple[str, dict]:
        """Rend (adresse de Droplet ID, attente). Gardez `attente` côté serveur."""
        verifier = _b64url(secrets.token_bytes(32))
        attente = {"verifier": verifier, "state": _b64url(secrets.token_bytes(16)), "nonce": _b64url(secrets.token_bytes(16))}
        params = {
            "client_id": self.client_id,
            "response_type": "code",
            "redirect_uri": self.redirect_uri,
            "scope": " ".join(self.portees),
            "code_challenge": _b64url(hashlib.sha256(verifier.encode()).digest()),
            "code_challenge_method": "S256",
            "state": attente["state"],
            "nonce": attente["nonce"],
        }
        if langue:
            params["ui_locales"] = langue
        return f"{self.configuration()['authorization_endpoint']}?{urllib.parse.urlencode(params)}", attente

    def terminer(self, url_de_retour: str, attente: dict | None) -> dict:
        """Au retour : vérifie tout et rend {sub, pseudo, id_token, access_token, ...}."""
        q = dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(url_de_retour).query))
        if "error" in q:
            raise ErreurDropletId(q["error"], q.get("error_description", ""))
        if not attente or q.get("state") != attente.get("state"):
            raise ErreurDropletId("state", "réponse inattendue (state)")
        if q.get("iss") and q["iss"] != self.emetteur:
            raise ErreurDropletId("iss", "émetteur inattendu")
        donnees = {
            "grant_type": "authorization_code",
            "code": q.get("code", ""),
            "redirect_uri": self.redirect_uri,
            "client_id": self.client_id,
            "code_verifier": attente["verifier"],
        }
        if self.client_secret:
            donnees["client_secret"] = self.client_secret
        t = _json(self.configuration()["token_endpoint"], donnees)
        claims = self.verifier_id_token(t["id_token"], attente["nonce"])
        pseudo = None
        if "profile" in self.portees:
            info = _json(self.configuration()["userinfo_endpoint"], entetes={"authorization": f"Bearer {t['access_token']}"})
            if info.get("sub") != claims["sub"]:
                raise ErreurDropletId("userinfo", "sub différent")
            pseudo = info.get("preferred_username")
        return {
            "sub": claims["sub"],
            "pseudo": pseudo,
            "id_token": t["id_token"],
            "access_token": t["access_token"],
            "refresh_token": t.get("refresh_token"),
            "expire_le": int(time.time()) + int(t.get("expires_in", 0)),
        }

    def verifier_id_token(self, jwt: str, nonce: str | None = None) -> dict:
        try:
            h, c, s = jwt.split(".")
        except ValueError:
            raise ErreurDropletId("id_token", "format") from None
        entete = json.loads(_de_b64url(h))
        claims = json.loads(_de_b64url(c))
        if entete.get("alg") != "ES256":
            raise ErreurDropletId("id_token", f"algorithme {entete.get('alg')}")
        brute = _de_b64url(s)
        if len(brute) != 64:
            raise ErreurDropletId("id_token", "signature")
        der = encode_dss_signature(int.from_bytes(brute[:32], "big"), int.from_bytes(brute[32:], "big"))
        try:
            self._cle(entete.get("kid")).verify(der, f"{h}.{c}".encode(), ec.ECDSA(hashes.SHA256()))
        except InvalidSignature:
            raise ErreurDropletId("id_token", "signature") from None
        maintenant = time.time()
        aud = claims.get("aud")
        if claims.get("iss") != self.emetteur:
            raise ErreurDropletId("id_token", "émetteur")
        if aud != self.client_id and not (isinstance(aud, list) and self.client_id in aud):
            raise ErreurDropletId("id_token", "audience")
        if claims.get("exp", 0) < maintenant - 60:
            raise ErreurDropletId("id_token", "expiré")
        if nonce and claims.get("nonce") != nonce:
            raise ErreurDropletId("id_token", "nonce")
        return claims

    def url_de_deconnexion(self, id_token: str, retour: str | None = None) -> str:
        p = {"id_token_hint": id_token, "client_id": self.client_id}
        if retour:
            p["post_logout_redirect_uri"] = retour
        return f"{self.configuration()['end_session_endpoint']}?{urllib.parse.urlencode(p)}"
