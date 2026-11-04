"""Sauvegardes Kunfox sur la boîte : écrire, relire, refuser une version plus ancienne."""
import base64, json, os, sys, time, urllib.request, urllib.error

B = 'http://127.0.0.1:8081'
ok = True

def req(m, chemin, corps=None):
    # le test de sécurité qui précède épuise la limite par IP : on patiente
    for _ in range(8):
        s, j = _req(m, chemin, corps)
        if s != 429: return s, j
        time.sleep(4)
    return s, j

def _req(m, chemin, corps=None):
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
s, _ = req('GET', f'/kunfox/{ident}'); print('   reçu', s); verifie('absente : 404', s == 404)
s, _ = req('PUT', f'/kunfox/{ident}', {'paquet': 'AAAA', 'version': 2}); verifie('écriture v2', s == 200)
s, j = req('GET', f'/kunfox/{ident}'); verifie('relecture v2', s == 200 and j.get('paquet') == 'AAAA' and j.get('version') == 2)
s, _ = req('PUT', f'/kunfox/{ident}', {'paquet': 'VIEUX', 'version': 1}); verifie('v1 refusée : 409', s == 409)
s, _ = req('PUT', f'/kunfox/{ident}', {'paquet': 'BBBB', 'version': 3}); verifie('écriture v3', s == 200)
s, j = req('GET', f'/kunfox/{ident}'); print('   reçu', s, j); verifie('relecture v3', j.get('paquet') == 'BBBB')
s, _ = req('GET', '/kunfox/court'); verifie('identifiant mal formé : 400', s == 400)
s, _ = req('PUT', f'/kunfox/{ident}', {'paquet': 'x' * 300000, 'version': 9}); verifie('trop grand : 413', s == 413)

# ── duels
qs = [{'question': f'Q{i}', 'options': ['a', 'b', 'c'], 'bonne': i % 3, 'explication': ''} for i in range(6)]
moi = {'nom': 'Awa', 'traces': [[1, 3000]] * 5 + [[0, 4000]]}
s, j = req('POST', '/kunfox/duels', {'lecon': 'maths_c_ch1_l1', 'titre': 'Les ensembles', 'matiere': 'Maths', 'questions': qs, 'createur': moi})
print('   reçu', s, j); verifie('duel créé : 201 et code', s == 201 and len(j.get('code', '')) == 8)
code = j.get('code', 'XXXXXXXX')
s, j = req('GET', f'/kunfox/duels/{code}')
verifie('duel relu', s == 200 and j['createur']['bonnes'] == 5 and j['createur']['ms'] == 19000 and len(j['questions']) == 6 and j['adversaires'] == [])
s, j = req('GET', f'/kunfox/duels/{code.lower()}'); verifie('code en minuscules accepté', s == 200)
s, j = req('POST', f'/kunfox/duels/{code}/resultat', {'nom': 'Moussa', 'traces': [[1, 2000]] * 6, 'avatar': 3})
verifie('résultat déposé', s == 200 and j.get('rang') == 1)
s, j = req('GET', f'/kunfox/duels/{code}')
verifie('adversaire visible', s == 200 and len(j['adversaires']) == 1 and j['adversaires'][0]['bonnes'] == 6 and j['adversaires'][0]['nom'] == 'Moussa')
s, _ = req('POST', f'/kunfox/duels/{code}/resultat', {'nom': 'Triche', 'traces': [[1, 1]] * 3}); verifie('mauvais nombre de réponses : 400', s == 400)
s, _ = req('POST', '/kunfox/duels', {'lecon': 'x', 'titre': 'y', 'questions': [], 'createur': moi}); verifie('sans questions : 400', s == 400)
s, _ = req('GET', '/kunfox/duels/ZZZZ2222'); verifie('duel inconnu : 404', s == 404)
s, _ = req('GET', '/kunfox/duels/abc'); verifie('code mal formé : 400', s == 400)
sys.exit(0 if ok else 1)
