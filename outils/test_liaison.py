# Test de bout en bout de la liaison Droplet Web, contre l'annuaire en ligne.
# Joue le téléphone (dépose l'enveloppe) et le navigateur (la relève et la
# déchiffre), avec exactement les mêmes algorithmes que l'app et le web :
# X25519 → HKDF-SHA256 (info droplet-lien-v1, sel droplet-mesh) → AES-256-GCM.
import base64, json, os, sys, time, urllib.request
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

A = sys.argv[1]
b64 = lambda b: base64.urlsafe_b64encode(b).decode().rstrip('=')
unb64 = lambda s: base64.urlsafe_b64decode(s + '=' * (-len(s) % 4))
raw = lambda pub: pub.public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
def cle(priv, pub):
    return HKDF(hashes.SHA256(), 32, salt=b'droplet-mesh', info=b'droplet-lien-v1').derive(priv.exchange(pub))
def req(url, method='GET', data=None, origin=None):
    r = urllib.request.Request(url, method=method, data=data, headers={'content-type': 'application/json', **({'origin': origin} if origin else {})})
    try:
        with urllib.request.urlopen(r, timeout=20) as x: return x.status, x.read().decode(), dict(x.headers)
    except urllib.error.HTTPError as e: return e.code, e.read().decode(), dict(e.headers)

navigateur = X25519PrivateKey.generate(); telephone = X25519PrivateKey.generate()
canal = b64(os.urandom(16))
print('health', req(A + '/health')[0])
print('vide', req(A + '/liaison/' + canal)[0], '(attendu 204)')
k = cle(telephone, navigateur.public_key()); nonce = os.urandom(12)
contenu = json.dumps({'peerId': 'test-ci', 'pseudo': 'Test', 'appareil': b64(os.urandom(9)), 'nom': 'CI · Linux'}).encode()
env = {'v': 1, 'cleTel': b64(raw(telephone.public_key())), 'nonce': b64(nonce), 'chiffre': b64(AESGCM(k).encrypt(nonce, contenu, None))}
print('depot', req(A + '/liaison/' + canal, 'POST', json.dumps(env).encode())[0], '(attendu 201)')
st, corps, h = req(A + '/liaison/' + canal, origin='https://web.dropletmesh.app')
print('releve', st, 'cors', h.get('access-control-allow-origin') or h.get('Access-Control-Allow-Origin'))
e = json.loads(corps)
k2 = cle(navigateur, X25519PublicKey := __import__('cryptography.hazmat.primitives.asymmetric.x25519', fromlist=['X']).X25519PublicKey.from_public_bytes(unb64(e['cleTel'])))
print('dechiffre', json.loads(AESGCM(k2).decrypt(unb64(e['nonce']), unb64(e['chiffre']), None)))
print('deuxieme releve', req(A + '/liaison/' + canal)[0], '(attendu 204 : remise une seule fois)')
st, _, h = req(A + '/liaison/' + canal, 'OPTIONS', origin='https://web.dropletmesh.app')
print('preflight', st, h.get('access-control-allow-methods') or h.get('Access-Control-Allow-Methods'))
print('etat', req(A + '/appareils/test-ci/abcdEF12/etat')[1])
print('revocation', req(A + '/appareils/test-ci/abcdEF12', 'DELETE')[0], req(A + '/appareils/test-ci/abcdEF12/etat')[1])
print('OK')
