# Génère lib/app/textes_langues.dart et vérifie que chaque langue a TOUTES
# les clés utilisées par le code.
import json, re, sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from fr_en import fr, en
from es_de_it_pt import es, de, it, pt
from ru_ar_hi_zh import ru, ar, hi, zh
L = dict(fr=fr, en=en, es=es, de=de, it=it, pt=pt, ru=ru, ar=ar, hi=hi, zh=zh)
from ajouts_ux import AJOUTS
for _l, _d in L.items():
    _d.update(AJOUTS[_l])
racine = pathlib.Path(__file__).parents[2] / 'apps/droplet_drop_flutter/lib'
code = '\n'.join(p.read_text() for p in racine.rglob('*.dart') if 'textes_langues' not in p.name and '/src/rust/' not in str(p))
utilisees = set(re.findall(r"\b(?:t|tr)\('([a-z0-9_]+)'", code)) - {'cle', 'accent', 'theme'}
dyn = {f'session_{x}' for x in ['ouverte', 'en_cours', 'pause', 'terminee']} | {f'couleur_{x}' for x in ['bleu', 'cyan', 'indigo', 'violet', 'vert']}
dyn |= {f'err_{x}' for x in ['connexion_interrompue', 'protocole', 'injoignable', 'empreinte_invalide', 'refuse', 'espace_insuffisant', 'session_invalide', 'session_expiree', 'fichier_introuvable', 'verification', 'annule', 'pause', 'connexion_securisee', 'acces_refuse']}
requises = utilisees | dyn
ok = True
for l, d in L.items():
    manque = requises - d.keys()
    if manque:
        ok = False
        print(l, 'MANQUE', sorted(manque))
    for k, v in d.items():
        if set(re.findall(r'\{(\w+)\}', v)) != set(re.findall(r'\{(\w+)\}', fr.get(k, v))):
            ok = False
            print(l, k, 'paramètres différents')
inutiles = set(fr) - requises
if inutiles:
    print('clés non utilisées :', sorted(inutiles))
sortie = ["// Généré par scripts/textes/generer.py — ne pas modifier à la main.", "const Map<String, Map<String, String>> textes = {"]
for l, d in L.items():
    sortie.append(f"  '{l}': {{")
    for k in sorted(d):
        sortie.append(f"    {json.dumps(k)}: {json.dumps(d[k], ensure_ascii=False)},".replace('$', r'\$'))
    sortie.append("  },")
sortie.append("};\n")
(racine / 'app/textes_langues.dart').write_text('\n'.join(sortie), encoding='utf-8')
print('OK' if ok else 'ÉCHEC', len(requises), 'clés')
sys.exit(0 if ok else 1)
