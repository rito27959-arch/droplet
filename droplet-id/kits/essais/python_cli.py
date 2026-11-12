# Petit programme d'essai du kit Python : `commencer` puis `terminer`.
import json, sys
sys.path.insert(0, __file__.rsplit("/", 2)[0] + "/python")
from droplet_id import DropletId
emetteur, client_id, retour, etape = sys.argv[1:5]
did = DropletId(client_id, retour, emetteur=emetteur, portees=["openid", "profile"])
if etape == "commencer":
    url, attente = did.commencer()
    print(json.dumps({"url": url, "attente": attente}))
else:
    s = did.terminer(sys.argv[5], json.loads(sys.argv[6]))
    print(json.dumps({"sub": s["sub"], "pseudo": s["pseudo"]}))
