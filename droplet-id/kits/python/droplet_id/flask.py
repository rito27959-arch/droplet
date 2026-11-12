"""
Droplet ID avec Flask, en trois lignes :

    from droplet_id.flask import blueprint
    app.secret_key = "…"   # la session Flask est signée
    app.register_blueprint(blueprint(client_id="mon-site", redirect_uri="https://mon-site.cm/connexion/retour"))

Routes : /connexion (part vers Droplet ID), /connexion/retour, /deconnexion.
Après connexion : session["droplet_id"] = {"sub": …, "pseudo": …}.
"""

from __future__ import annotations

from urllib.parse import urlsplit

from flask import Blueprint, redirect, request, session

from . import DropletId, ErreurDropletId, EMETTEUR


def blueprint(*, client_id: str, redirect_uri: str, client_secret: str | None = None, emetteur: str = EMETTEUR,
              portees: list[str] | None = None, apres: str = "/", echec: str = "/?erreur=connexion") -> Blueprint:
    did = DropletId(client_id, redirect_uri, client_secret=client_secret, emetteur=emetteur, portees=portees)
    bp = Blueprint("droplet_id", __name__)
    chemin_retour = urlsplit(redirect_uri).path

    @bp.get("/connexion")
    def connexion():
        url, attente = did.commencer(langue=request.args.get("langue"))
        session["droplet_id_attente"] = attente
        return redirect(url)

    @bp.get(chemin_retour)
    def retour():
        attente = session.pop("droplet_id_attente", None)
        try:
            s = did.terminer(request.url, attente)
        except ErreurDropletId as e:
            return redirect(f"{echec}&code={e.code}")
        session["droplet_id"] = {"sub": s["sub"], "pseudo": s["pseudo"]}
        return redirect(apres)

    @bp.get("/deconnexion")
    def deconnexion():
        session.pop("droplet_id", None)
        return redirect(apres)

    return bp
