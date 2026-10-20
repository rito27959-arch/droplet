# Test d'intégration : annuaire + boîte aux lettres + Postgres.
import base64, hashlib, hmac, json, os, subprocess, sys, threading, time, urllib.request
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes, serialization

ANN, BOI = 'http://127.0.0.1:8080', 'http://127.0.0.1:8081'
SERVEUR_PUB = X25519PublicKey.from_public_bytes(base64.b64decode(os.environ['CLE_PUBLIQUE']))
ok = True
def verifier(nom, cond):
    global ok
    print(('✅ ' if cond else '❌ ') + nom); ok &= bool(cond)

def req(url, methode='GET', corps=None, entetes=None):
    data = json.dumps(corps).encode() if corps is not None else None
    r = urllib.request.Request(url, method=methode, data=data, headers={'content-type': 'application/json', **(entetes or {})})
    try:
        with urllib.request.urlopen(r, timeout=40) as x: return x.status, x.read().decode()
    except urllib.error.HTTPError as e: return e.code, e.read().decode()

class Appareil:
    def __init__(s, nom):
        s.cle = X25519PrivateKey.generate()
        s.pub = base64.b64encode(s.cle.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode()
        s.id = hashlib.sha256((nom + str(time.time())).encode()).hexdigest()
        s.k = HKDF(hashes.SHA256(), 32, salt=b'droplet-mesh', info=b'droplet-auth-v1').derive(s.cle.exchange(SERVEUR_PUB))
    def signer(s, methode, chemin, corps=b''):
        ts = str(int(time.time())); nonce = base64.urlsafe_b64encode(os.urandom(16)).decode().rstrip('=')
        canon = f"{methode}\n{chemin}\n{ts}\n{nonce}\n{hashlib.sha256(corps).hexdigest()}"
        sig = base64.urlsafe_b64encode(hmac.new(s.k, canon.encode(), hashlib.sha256).digest()).decode().rstrip('=')
        return {'x-droplet-id': s.id, 'x-droplet-ts': ts, 'x-droplet-nonce': nonce, 'x-droplet-sig': sig}
    def inscription(s, signe=False, pub=None):
        corps = {'peerId': s.id, 'pseudo': 'Testeur', 'onion': 'x.onion', 'publicKey': pub or s.pub}
        brut = json.dumps(corps).encode()
        e = s.signer('POST', '/register', brut) if signe else {}
        r = urllib.request.Request(ANN + '/register', method='POST', data=brut, headers={'content-type': 'application/json', **e})
        try:
            with urllib.request.urlopen(r) as x: return x.status
        except urllib.error.HTTPError as e2: return e2.code

alice, bob, pirate = Appareil('alice'), Appareil('bob'), Appareil('pirate')
verifier('inscription sans signature (ancienne app) acceptée', alice.inscription() == 200)
verifier('bob inscrit', bob.inscription() == 200)
# Un téléphone NEUF dont la toute première inscription est déjà signée :
# l'annuaire doit vérifier avec la clé présentée (bug du 20 octobre : 401).
neuf = Appareil('neuf')
verifier('première inscription signée acceptée', neuf.inscription(signe=True) == 200)
verifier('…et la boîte reconnaît aussitôt sa clé', req(BOI + '/messages/' + neuf.id, entetes=neuf.signer('GET', '/messages/' + neuf.id))[0] == 200)
verifier('le pirate ne peut pas remplacer la clé d’Alice', pirate.inscription(pub=pirate.pub) == 200 and
         req(ANN + '/register', 'POST', {'peerId': alice.id, 'pseudo': 'P', 'onion': 'p.onion', 'publicKey': pirate.pub})[0] == 409)
verifier('/notify refusé sans clé interne', req(ANN + '/notify', 'POST', {'peerId': alice.id, 'title': 'x', 'body': 'y'})[0] == 403)
verifier('/notify accepté avec la clé interne', req(ANN + '/notify', 'POST', {'peerId': alice.id, 'title': 'x', 'body': 'y'}, {'x-cle-interne': os.environ['CLE_INTERNE']})[0] == 200)

# Boîte aux lettres
st, c = req(BOI + '/messages', 'POST', {'from': bob.id, 'to': alice.id, 'payload': 'chiffre-1'})
verifier('dépôt sans signature (ancienne app)', st == 200)
st, c = req(BOI + '/messages/' + alice.id)
verifier('relève sans signature tant qu’Alice n’a jamais signé', st == 200 and json.loads(c)['count'] == 1)
chemin = '/messages/' + alice.id
st, c = req(BOI + chemin, entetes=alice.signer('GET', chemin))
verifier('relève signée acceptée', st == 200)
verifier('après signature, relève non signée REFUSÉE', req(BOI + chemin)[0] == 401)
verifier('signature du pirate refusée', req(BOI + chemin, entetes={**pirate.signer('GET', chemin), 'x-droplet-id': alice.id})[0] == 401)
e = alice.signer('GET', chemin); req(BOI + chemin, entetes=e)
verifier('rejeu de la même signature refusé', req(BOI + chemin, entetes=e)[0] == 401)
vieux = alice.signer('GET', chemin); vieux['x-droplet-ts'] = str(int(time.time()) - 900)
verifier('signature périmée refusée', req(BOI + chemin, entetes=vieux)[0] == 401)
verifier('le pirate ne dépose plus au nom d’Alice', req(BOI + '/messages', 'POST', {'from': alice.id, 'to': bob.id, 'payload': 'faux'})[0] == 401)

# Attente longue
resultat = {}
def attendre():
    t0 = time.time(); st, c = req(BOI + chemin + '?attendre=20', entetes=alice.signer('GET', chemin))
    resultat['duree'] = time.time() - t0; resultat['n'] = json.loads(c)['count'] if st == 200 else -1
id_msg = json.loads(req(BOI + chemin, entetes=alice.signer('GET', chemin))[1])['messages'][0]['id']
req(BOI + chemin + '/' + id_msg, 'DELETE', entetes=alice.signer('DELETE', chemin + '/' + id_msg))
th = threading.Thread(target=attendre); th.start(); time.sleep(2)
req(BOI + '/messages', 'POST', {'from': bob.id, 'to': alice.id, 'payload': 'chiffre-2'}); th.join()
verifier(f"attente longue réveillée par le dépôt ({resultat.get('duree', 0):.1f} s)", resultat.get('n') == 1 and resultat['duree'] < 8)

# Persistance : on redémarre la boîte
subprocess.run(['pkill', '-f', '/tmp/boite'])
time.sleep(1); subprocess.Popen(['/tmp/boite'], env={**os.environ, 'PORT': '8081'}, stdout=open('/tmp/boite.log', 'a'), stderr=subprocess.STDOUT); time.sleep(3)
st, c = req(BOI + chemin, entetes=alice.signer('GET', chemin))
verifier('le message survit au redémarrage', st == 200 and json.loads(c)['count'] == 1)
subprocess.run(['pkill', '-f', '/tmp/annuaire'])
time.sleep(1); subprocess.Popen(['/tmp/annuaire'], env={**os.environ, 'PORT': '8080'}, stdout=open('/tmp/annuaire.log', 'a'), stderr=subprocess.STDOUT); time.sleep(3)
verifier('la protection d’Alice survit au redémarrage de l’annuaire',
         req(ANN + '/register', 'POST', {'peerId': alice.id, 'pseudo': 'P', 'onion': 'p.onion', 'publicKey': pirate.pub})[0] in (401, 409))
verifier('Alice (signée) se réinscrit normalement', alice.inscription(signe=True) == 200)
st, c = req(ANN + '/search?q=Testeur')
verifier('l’inscription survit au redémarrage', st == 200 and len(json.loads(c)['results']) >= 1)

# Appareils liés (Droplet Web)
def signee(qui, methode, chemin, corps=None, base=BOI, entetes=None):
    brut = json.dumps(corps).encode() if corps is not None else b''
    e = {**qui.signer(methode, chemin, brut), **(entetes or {})}
    r = urllib.request.Request(base + chemin, method=methode, data=brut if corps is not None else None,
                               headers={'content-type': 'application/json', **e})
    try:
        with urllib.request.urlopen(r, timeout=40) as x: return x.status, x.read().decode(), dict(x.headers)
    except urllib.error.HTTPError as e2: return e2.code, e2.read().decode(), dict(e2.headers)
nav = Appareil('navigateur'); nav.id = base64.urlsafe_b64encode(os.urandom(9)).decode()
chemin_cle = f'/appareils/{alice.id}/{nav.id}/cle'
verifier('déclarer un appareil sans signature : refusé', req(ANN + chemin_cle, 'POST', {'cle': nav.pub})[0] == 401)
verifier('le pirate ne peut pas attacher un appareil au compte d’Alice',
         signee(pirate, 'POST', chemin_cle, {'cle': pirate.pub}, base=ANN, entetes={'x-droplet-id': alice.id})[0] == 401)
verifier('Alice déclare son navigateur', signee(alice, 'POST', chemin_cle, {'cle': nav.pub}, base=ANN)[0] == 200)
verifier('une autre clé pour le même appareil : refusée', signee(alice, 'POST', chemin_cle, {'cle': pirate.pub}, base=ANN)[0] == 409)
chemin_nav = '/messages/' + nav.id
verifier('le navigateur relève sa file, signé', signee(nav, 'GET', chemin_nav)[0] == 200)
verifier('sa file non signée : refusée', req(BOI + chemin_nav)[0] == 401)
verifier('le téléphone dépose un lot pour le navigateur', signee(alice, 'POST', '/messages', {'from': alice.id, 'to': nav.id, 'payload': '{"w":1}'})[0] == 200)
st, c, _ = signee(nav, 'GET', chemin_nav)
verifier('le navigateur reçoit le lot', st == 200 and json.loads(c)['count'] == 1 and json.loads(c)['messages'][0]['from'] == alice.id)
verifier('le navigateur dépose une demande pour le téléphone', signee(nav, 'POST', '/messages', {'from': nav.id, 'to': alice.id, 'payload': '{"l":1}'})[0] == 200)
verifier('personne ne dépose au nom du navigateur', req(BOI + '/messages', 'POST', {'from': nav.id, 'to': alice.id, 'payload': 'x'})[0] == 401)
o = urllib.request.Request(BOI + '/messages', method='OPTIONS', headers={'origin': 'https://web.dropletmesh.app', 'access-control-request-method': 'POST'})
with urllib.request.urlopen(o) as x: h = dict(x.headers)
verifier('la boîte accepte Droplet Web (CORS, en-têtes de signature)', h.get('access-control-allow-origin') == 'https://web.dropletmesh.app' and 'x-droplet-sig' in h.get('access-control-allow-headers', ''))
_, _, h = signee(alice, 'GET', '/search', base=ANN, entetes={'origin': 'https://web.dropletmesh.app'}) if False else (0, 0, {})
o = urllib.request.Request(ANN + '/search?q=Te', headers={'origin': 'https://web.dropletmesh.app'})
with urllib.request.urlopen(o) as x: h = dict(x.headers); trouves = json.loads(x.read().decode())['results']
verifier('la recherche par pseudo répond à Droplet Web (CORS)', h.get('access-control-allow-origin') == 'https://web.dropletmesh.app' and len(trouves) >= 1)
verifier('l’appareil n’apparaît pas dans la recherche', all(t['peerId'] != nav.id for t in trouves))
chemin_rev = f'/appareils/{alice.id}/{nav.id}'
verifier('déconnexion non signée : refusée', req(ANN + chemin_rev, 'DELETE')[0] == 401)
verifier('Alice déconnecte son navigateur', signee(alice, 'DELETE', chemin_rev, base=ANN)[0] == 200)
verifier('le navigateur déconnecté ne relève plus rien', signee(nav, 'GET', chemin_nav)[0] == 401)
verifier('l’annuaire dit au navigateur qu’il est déconnecté', json.loads(req(ANN + chemin_rev + '/etat')[1])['lie'] is False)
verifier('on ne relie pas un appareil déconnecté', signee(alice, 'POST', chemin_cle, {'cle': nav.pub}, base=ANN)[0] == 410)

# Débit
codes = [req(BOI + '/messages', 'POST', {'from': bob.id, 'to': pirate.id, 'payload': 'x'})[0] for _ in range(80)]
verifier(f'inondation freinée (429 après {codes.index(429) if 429 in codes else "∞"} dépôts)', 429 in codes)
print('RÉSULTAT', 'OK' if ok else 'ÉCHEC'); sys.exit(0 if ok else 1)
