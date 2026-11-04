"""Sauvegardes Kunfox sur la boîte : écrire, relire, refuser une version plus ancienne."""
import base64, json, os, sys, urllib.request, urllib.error

B = 'http://127.0.0.1:8081'
ok = True

def req(m, chemin, corps=None):
    d = json.dumps(corps).encode() if corps is not None else None
    r = urllib.request.Request(B + chemin, data=d, method=m, headers={'content-type': 'application/json'})
    try:
        with urllib.request.urlopen(r) as f:
            return f.status, json.loads(f.read() or b'{}')
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b'{}')

def verifie(nom, cond):
    global ok
    print(('OK   ' if cond else 'ÉCHEC ') + nom)
    ok = ok and cond

ident = base64.urlsafe_b64encode(os.urandom(32)).decode().rstrip('=')
verifie('identifiant de 43 caractères', len(ident) == 43)
s, _ = req('GET', f'/kunfox/{ident}'); verifie('absente : 404', s == 404)
s, _ = req('PUT', f'/kunfox/{ident}', {'paquet': 'AAAA', 'version': 2}); verifie('écriture v2', s == 200)
s, j = req('GET', f'/kunfox/{ident}'); verifie('relecture v2', s == 200 and j.get('paquet') == 'AAAA' and j.get('version') == 2)
s, _ = req('PUT', f'/kunfox/{ident}', {'paquet': 'VIEUX', 'version': 1}); verifie('v1 refusée : 409', s == 409)
s, _ = req('PUT', f'/kunfox/{ident}', {'paquet': 'BBBB', 'version': 3}); verifie('écriture v3', s == 200)
s, j = req('GET', f'/kunfox/{ident}'); print('   reçu', s, j); verifie('relecture v3', j.get('paquet') == 'BBBB')
s, _ = req('GET', '/kunfox/court'); verifie('identifiant mal formé : 400', s == 400)
s, _ = req('PUT', f'/kunfox/{ident}', {'paquet': 'x' * 300000, 'version': 9}); verifie('trop grand : 413', s == 413)
sys.exit(0 if ok else 1)
