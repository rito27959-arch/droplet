// ============================================================================
// LE COMPTE OFFICIEL DROPLET — côté serveur.
// ----------------------------------------------------------------------------
// C'est d'ici que partent les nouveautés de Droplet : une page
// d'administration (`/admin/annonces`) pour écrire une annonce en plusieurs
// langues, la signer et la publier ; et le fichier que les téléphones
// viennent lire (`/annonces.json`).
//
// ── ⚠️ CE QUI REND LE COMPTE « CERTIFIÉ » ─────────────────────────────
//
// Chaque annonce est SIGNÉE en Ed25519 par ce serveur. La clé publique
// correspondante est gravée dans l'application (`CompteDroplet`) : un
// téléphone n'affiche une annonce dans la conversation « Droplet » (avec la
// coche officielle) que si la signature est bonne. Les annonces voyagent
// ensuite aussi de téléphone en téléphone, sans Internet : n'importe qui
// peut les relayer, personne ne peut en fabriquer ni en modifier une.
//
// ── LA CLÉ PRIVÉE ────────────────────────────────────────────────────
//
// Créée au premier démarrage, rangée sur le volume (`/data/annonces_cle`,
// lisible par le seul propriétaire), jamais renvoyée par aucune route. La
// clé PUBLIQUE est écrite dans le journal au démarrage et servie par
// `/annonces/cle` : c'est elle qu'on colle dans l'application.
//
// ⚠️ PERDRE CE FICHIER, c'est rendre muettes toutes les applications
// installées (elles refuseraient les annonces signées par une nouvelle
// clé). Pour le sauvegarder ou le déplacer, la variable `ANNONCES_CLE`
// (la graine, en base64) a priorité sur le fichier.
//
// ── QUI PEUT PUBLIER ─────────────────────────────────────────────────
//
// Seul le porteur de `ADMIN_KEY` (en-tête `X-Admin-Key`), la même clé que
// la modération. Sans `ADMIN_KEY` configurée, la publication est fermée.
//
// ⚠️ LE TEXTE SIGNÉ doit rester identique, octet pour octet, à
// `AnnoncesDroplet._canonique` dans l'application et à `canonique()` dans
// `outils/annonce_droplet.py`.
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:shelf/shelf.dart';

/// Les langues de l'application.
const List<String> languesAnnonce = ['fr', 'en', 'es', 'pt', 'de', 'it', 'ar', 'hi', 'ru', 'zh'];

/// Version du format signé (`CompteDroplet.versionFormat`).
const int versionFormatAnnonce = 1;

class CompteOfficiel {
  CompteOfficiel._(this._stock, this._paire, this.clePublique, this._annonces);

  final File _stock;
  final SimpleKeyPair _paire;

  /// La clé publique, en base64 — celle de `CompteDroplet.clePubliqueBase64`.
  final String clePublique;
  final List<Map<String, dynamic>> _annonces;

  static final Ed25519 _algo = Ed25519();

  /// Ouvre le compte : la clé (variable, fichier, ou nouvelle) et les
  /// annonces déjà publiées.
  static Future<CompteOfficiel> ouvrir(Directory dossier) async {
    dossier.createSync(recursive: true);
    final fichierCle = File('${dossier.path}/annonces_cle');
    List<int> graine;
    final env = Platform.environment['ANNONCES_CLE'] ?? '';
    if (env.isNotEmpty) {
      graine = base64.decode(env.trim());
    } else if (fichierCle.existsSync()) {
      graine = base64.decode(fichierCle.readAsStringSync().trim());
    } else {
      final r = Random.secure();
      graine = List<int>.generate(32, (_) => r.nextInt(256));
      fichierCle.writeAsStringSync(base64.encode(graine));
      try {
        await Process.run('chmod', ['600', fichierCle.path]);
      } catch (_) {}
      print('[Annonces] Nouvelle clé de signature créée dans ${fichierCle.path}');
    }
    if (graine.length != 32) {
      throw StateError('Clé d\'annonces invalide (32 octets attendus)');
    }
    final paire = await _algo.newKeyPairFromSeed(graine);
    final publique = base64.encode((await paire.extractPublicKey()).bytes);

    final stock = File('${dossier.path}/annonces.json');
    var annonces = <Map<String, dynamic>>[];
    if (stock.existsSync()) {
      try {
        annonces = [
          for (final a in jsonDecode(stock.readAsStringSync()) as List) Map<String, dynamic>.from(a as Map),
        ];
      } catch (e) {
        print('[Annonces] ⚠️ annonces.json illisible ($e) — on repart d\'une liste vide');
      }
    }
    print('[Annonces] Compte officiel prêt : ${annonces.length} annonce(s). '
        'Clé publique à graver dans l\'application : $publique');
    return CompteOfficiel._(stock, paire, publique, annonces);
  }

  // ── La signature ─────────────────────────────────────────────────────

  static String _plat(String v) => v.replaceAll('\\', r'\\').replaceAll('\n', r'\n').replaceAll('\r', '');

  /// Le texte exact qui est signé (voir l'en-tête).
  static String canonique(Map<String, dynamic> a) {
    final lignes = <String>[
      _plat(a['id'] as String),
      '$versionFormatAnnonce',
      _plat(a['date'] as String),
      _plat(a['versionMini'] as String),
      _plat(a['lien'] as String),
    ];
    final textes = a['textes'] as Map<String, dynamic>;
    final langues = textes.keys.toList()..sort();
    for (final lg in langues) {
      final t = textes[lg] as Map<String, dynamic>;
      lignes
        ..add(_plat(lg))
        ..add(_plat(t['titre'] as String))
        ..add(_plat(t['corps'] as String));
    }
    return lignes.join('\n');
  }

  Future<String> _signer(Map<String, dynamic> a) async {
    final s = await _algo.sign(utf8.encode(canonique(a)), keyPair: _paire);
    return base64.encode(s.bytes);
  }

  void _sauver() {
    final tmp = File('${_stock.path}.tmp');
    tmp.writeAsStringSync(jsonEncode(_annonces));
    tmp.renameSync(_stock.path);
  }

  // ── Les routes publiques ─────────────────────────────────────────────

  /// `GET /annonces.json` — ce que les téléphones viennent lire. Les plus
  /// récentes d'abord, trente au plus.
  Response lot(Request r) {
    final tri = [..._annonces]..sort((x, y) => (y['date'] as String).compareTo(x['date'] as String));
    return Response.ok(
      jsonEncode(tri.take(30).toList()),
      headers: {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'public, max-age=300',
        'access-control-allow-origin': '*',
      },
    );
  }

  /// `GET /annonces/cle` — la clé publique (publique par nature).
  Response cle(Request r) => Response.ok(
        jsonEncode({'cle': clePublique, 'format': versionFormatAnnonce}),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  // ── La publication (clé admin) ───────────────────────────────────────

  static final RegExp _idValide = RegExp(r'^[a-z0-9][a-z0-9-]{2,59}$');

  /// `POST /admin/annonces` — publie une annonce. Corps :
  /// `{id?, versionMini?, lien?, textes: {fr: {titre, corps}, …}}`.
  Future<Response> publier(Request r) async {
    final brut = await r.readAsString();
    if (brut.length > 64 * 1024) return _erreur(413, 'Annonce trop longue');
    Map<String, dynamic> e;
    try {
      e = Map<String, dynamic>.from(jsonDecode(brut) as Map);
    } catch (_) {
      return _erreur(400, 'JSON illisible');
    }
    final textesBruts = e['textes'];
    if (textesBruts is! Map || textesBruts.isEmpty) return _erreur(400, 'Il faut au moins une langue');
    final textes = <String, dynamic>{};
    for (final entree in textesBruts.entries) {
      final lg = '${entree.key}';
      final v = entree.value;
      if (!languesAnnonce.contains(lg)) return _erreur(400, 'Langue inconnue : $lg');
      if (v is! Map) continue;
      final titre = '${v['titre'] ?? ''}'.trim();
      final corps = '${v['corps'] ?? ''}'.trim();
      if (titre.isEmpty && corps.isEmpty) continue;
      if (titre.isEmpty || corps.isEmpty) return _erreur(400, 'Titre et texte requis ($lg)');
      if (titre.length > 120) return _erreur(400, 'Titre trop long ($lg) : 120 caractères au plus');
      if (corps.length > 4000) return _erreur(400, 'Texte trop long ($lg) : 4000 caractères au plus');
      textes[lg] = {'titre': titre, 'corps': corps};
    }
    if (textes.isEmpty) return _erreur(400, 'Il faut au moins une langue remplie');
    if (!textes.containsKey('fr') && !textes.containsKey('en')) {
      return _erreur(400, 'Le français ou l\'anglais est requis (langue de repli)');
    }
    final maintenant = DateTime.now().toUtc();
    final date = '${maintenant.toIso8601String().split('.').first}Z';
    var id = '${e['id'] ?? ''}'.trim().toLowerCase();
    if (id.isEmpty) {
      final titre = ((textes['fr'] ?? textes['en']) as Map)['titre'] as String;
      final slug = titre
          .toLowerCase()
          .replaceAll(RegExp(r'[àâä]'), 'a')
          .replaceAll(RegExp(r'[éèêë]'), 'e')
          .replaceAll(RegExp(r'[îï]'), 'i')
          .replaceAll(RegExp(r'[ôö]'), 'o')
          .replaceAll(RegExp(r'[ùûü]'), 'u')
          .replaceAll('ç', 'c')
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      id = '${date.substring(0, 10)}-${slug.isEmpty ? 'annonce' : slug}';
      if (id.length > 60) id = id.substring(0, 60).replaceAll(RegExp(r'-+$'), '');
    }
    if (!_idValide.hasMatch(id)) return _erreur(400, 'Identifiant invalide (minuscules, chiffres, tirets)');
    // ⚠️ UN IDENTIFIANT NE SERT QU'UNE FOIS. Les téléphones ignorent une
    // annonce déjà vue : republier sous le même identifiant ne montrerait
    // rien à ceux qui ont reçu la première version.
    if (_annonces.any((a) => a['id'] == id)) return _erreur(409, 'Cet identifiant a déjà servi : $id');
    final versionMini = '${e['versionMini'] ?? ''}'.trim();
    final lien = '${e['lien'] ?? ''}'.trim();
    if (lien.isNotEmpty && !lien.startsWith('https://')) return _erreur(400, 'Le lien doit commencer par https://');
    final annonce = <String, dynamic>{
      'id': id,
      'version': versionFormatAnnonce,
      'date': date,
      'versionMini': versionMini,
      'lien': lien,
      'textes': textes,
    };
    annonce['signature'] = await _signer(annonce);
    _annonces.add(annonce);
    _sauver();
    print('[Annonces] Publiée : $id (${textes.keys.join(', ')})');
    return Response(201, body: jsonEncode(annonce), headers: {'content-type': 'application/json; charset=utf-8'});
  }

  /// `GET /admin/annonces/liste` — toutes les annonces, pour la page.
  Response liste(Request r) => Response.ok(
        jsonEncode(([..._annonces]..sort((x, y) => (y['date'] as String).compareTo(x['date'] as String)))),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  /// `DELETE /admin/annonces/<id>` — retire une annonce du serveur.
  ///
  /// ⚠️ Les téléphones qui l'ont déjà reçue la gardent : on ne reprend pas
  /// un message envoyé. Le retrait empêche seulement les suivants de la
  /// recevoir.
  Response retirer(Request r, String id) {
    final avant = _annonces.length;
    _annonces.removeWhere((a) => a['id'] == id);
    if (_annonces.length == avant) return _erreur(404, 'Annonce introuvable');
    _sauver();
    print('[Annonces] Retirée : $id');
    return Response.ok(jsonEncode({'retiree': id}), headers: {'content-type': 'application/json'});
  }

  Response _erreur(int code, String message) =>
      Response(code, body: jsonEncode({'error': message}), headers: {'content-type': 'application/json; charset=utf-8'});

  /// `GET /admin/annonces` — la page de publication.
  Response page(Request r) => Response.ok(
        _pageAdmin,
        headers: {
          'content-type': 'text/html; charset=utf-8',
          'cache-control': 'no-store',
          // La page ne charge rien d'ailleurs et ne se laisse pas encadrer.
          'content-security-policy': "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; frame-ancestors 'none'",
          'x-frame-options': 'DENY',
        },
      );
}

// ─────────────────────────────────────────────────────────────
//  LA PAGE DE PUBLICATION
// ─────────────────────────────────────────────────────────────
//
// Une seule page, sans dépendance : la clé admin est tapée une fois et
// gardée dans l'onglet (sessionStorage), jamais dans l'adresse. Aperçu en
// bulle avant publication, comme le verra un téléphone.

const String _pageAdmin = r'''<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Droplet · Annonces</title>
<style>
:root{--fond:#f2f2f7;--carte:#fff;--texte:#1d1d1f;--texte2:#6e6e73;--accent:#0a84ff;--trait:#d1d1d6;--rouge:#ff3b30;--vert:#34c759}
@media (prefers-color-scheme:dark){:root{--fond:#000;--carte:#1c1c1e;--texte:#f5f5f7;--texte2:#98989d;--trait:#38383a}}
*{box-sizing:border-box}body{margin:0;background:var(--fond);color:var(--texte);font:16px/1.4 -apple-system,system-ui,"Segoe UI",Roboto,sans-serif}
main{max-width:720px;margin:0 auto;padding:24px 16px 80px}
h1{font-size:28px;margin:8px 0 4px;display:flex;align-items:center;gap:10px}
.coche{display:inline-grid;place-items:center;width:22px;height:22px;border-radius:50%;background:var(--accent);color:#fff;font-size:14px}
p.sous{color:var(--texte2);margin:0 0 20px}
.carte{background:var(--carte);border-radius:14px;padding:16px;margin:14px 0}
label{display:block;font-size:13px;color:var(--texte2);margin:12px 0 6px;text-transform:uppercase;letter-spacing:.04em}
input,textarea{width:100%;padding:11px 12px;border:1px solid var(--trait);border-radius:10px;background:var(--fond);color:var(--texte);font:inherit}
textarea{min-height:110px;resize:vertical}
details{margin-top:8px}summary{cursor:pointer;color:var(--accent);padding:8px 0}
.lg{border-top:1px solid var(--trait);padding-top:10px;margin-top:10px}
.lg b{font-size:14px}
button{border:0;border-radius:12px;padding:13px 18px;font:600 16px/1 inherit;cursor:pointer}
.principal{background:var(--accent);color:#fff;width:100%}
.secondaire{background:transparent;color:var(--accent)}
.danger{background:transparent;color:var(--rouge);padding:6px 0}
.ligne{display:flex;gap:10px}.ligne>*{flex:1}
#apercu{display:none}.tel{background:var(--fond);border-radius:18px;padding:14px}
.entete{display:flex;align-items:center;gap:8px;font-weight:600;margin-bottom:10px}
.av{width:30px;height:30px;border-radius:50%;background:var(--accent);display:grid;place-items:center;color:#fff}
.bulle{background:var(--carte);border-radius:18px 18px 18px 6px;padding:10px 14px;max-width:88%;white-space:pre-wrap}
.bulle b{display:block;margin-bottom:4px}
.msg{padding:10px 12px;border-radius:10px;margin:10px 0;display:none}
.ok{background:rgba(52,199,89,.15);color:var(--vert)}.ko{background:rgba(255,59,48,.12);color:var(--rouge)}
.publiee{border-top:1px solid var(--trait);padding:12px 0}.publiee:first-child{border-top:0}
.publiee small{color:var(--texte2)}
</style>
</head>
<body>
<main>
<h1>Droplet <span class="coche">✓</span></h1>
<p class="sous">Le compte officiel. Chaque annonce est signée par le serveur et apparaît dans la conversation « Droplet » de chaque téléphone — par Internet, ou de téléphone en téléphone sans réseau.</p>

<div class="carte">
  <label for="cle">Clé d'administration</label>
  <input id="cle" type="password" autocomplete="current-password" placeholder="ADMIN_KEY">
</div>

<div class="carte">
  <label>Français</label>
  <input id="t-fr" placeholder="Titre (ex. : Les stickers arrivent)">
  <textarea id="c-fr" placeholder="Le texte de l'annonce…"></textarea>
  <label>English</label>
  <input id="t-en" placeholder="Title">
  <textarea id="c-en" placeholder="Announcement text…"></textarea>
  <details><summary>Autres langues (facultatif — sinon l'anglais s'affiche)</summary><div id="autres"></div></details>
  <details><summary>Options</summary>
    <label for="lien">Lien (https://…)</label><input id="lien" placeholder="https://dropletmesh.app/…">
    <label for="vmin">Version minimale de l'app</label><input id="vmin" placeholder="1.4.0">
    <label for="id">Identifiant (sinon tiré du titre)</label><input id="id" placeholder="2026-11-stickers">
  </details>
</div>

<div class="carte" id="apercu"><div class="tel"><div class="entete"><span class="av">💧</span>Droplet <span class="coche">✓</span></div><div class="bulle" id="bulle"></div></div></div>
<div class="msg" id="msg"></div>
<div class="ligne"><button class="secondaire" id="voir">Aperçu</button><button class="principal" id="publier">Publier</button></div>

<div class="carte"><label>Déjà publiées</label><div id="liste"><small>Entrez la clé pour voir la liste.</small></div></div>
</main>
<script>
const autres={es:'Español',pt:'Português',de:'Deutsch',it:'Italiano',ar:'العربية',hi:'हिन्दी',ru:'Русский',zh:'中文'};
const $=id=>document.getElementById(id);
for(const [lg,nom] of Object.entries(autres)){const d=document.createElement('div');d.className='lg';d.innerHTML='<b></b><input placeholder="Titre"><textarea placeholder="Texte"></textarea>';d.querySelector('b').textContent=nom;d.querySelector('input').id='t-'+lg;d.querySelector('textarea').id='c-'+lg;$('autres').appendChild(d);}
try{$('cle').value=sessionStorage.getItem('cle')||''}catch(e){}
$('cle').addEventListener('change',()=>{try{sessionStorage.setItem('cle',$('cle').value)}catch(e){};charger();});
function textes(){const t={};for(const lg of ['fr','en',...Object.keys(autres)]){const ti=$('t-'+lg).value.trim(),co=$('c-'+lg).value.trim();if(ti||co)t[lg]={titre:ti,corps:co};}return t;}
function dire(t,ok){const m=$('msg');m.textContent=t;m.className='msg '+(ok?'ok':'ko');m.style.display='block';}
$('voir').onclick=()=>{const t=textes();const x=t.fr||t.en||Object.values(t)[0];if(!x){dire('Écrivez au moins le titre et le texte en français.',false);return;}const b=$('bulle');b.textContent='';const ti=document.createElement('b');ti.textContent=x.titre;b.appendChild(ti);b.appendChild(document.createTextNode(x.corps));$('apercu').style.display='block';};
$('publier').onclick=async()=>{
  const corps={textes:textes(),lien:$('lien').value.trim(),versionMini:$('vmin').value.trim(),id:$('id').value.trim()};
  if(!confirm('Publier cette annonce à tous les utilisateurs de Droplet ? Une annonce reçue ne peut pas être reprise.'))return;
  const r=await fetch('/admin/annonces',{method:'POST',headers:{'content-type':'application/json','x-admin-key':$('cle').value},body:JSON.stringify(corps)});
  const j=await r.json().catch(()=>({}));
  if(r.ok){dire('Publiée et signée : '+j.id+'. Les téléphones la reçoivent à leur prochaine vérification (12 h au plus), ou de leurs voisins.',true);charger();}
  else dire(j.error||('Erreur '+r.status),false);
};
async function charger(){
  const r=await fetch('/admin/annonces/liste',{headers:{'x-admin-key':$('cle').value}});
  const l=$('liste');l.textContent='';
  if(!r.ok){l.innerHTML='<small>Clé invalide ou publication désactivée.</small>';return;}
  const a=await r.json();if(!a.length){l.innerHTML='<small>Aucune annonce pour l\'instant.</small>';return;}
  for(const x of a){const d=document.createElement('div');d.className='publiee';const t=x.textes.fr||x.textes.en||Object.values(x.textes)[0];
    const b=document.createElement('b');b.textContent=t.titre;const s=document.createElement('small');s.textContent=' · '+x.date.replace('T',' ').replace('Z','')+' · '+Object.keys(x.textes).join(' ');
    const k=document.createElement('button');k.className='danger';k.textContent='Retirer du serveur';
    k.onclick=async()=>{if(!confirm('Retirer « '+t.titre+' » ? Les téléphones qui l\'ont déjà reçue la garderont.'))return;await fetch('/admin/annonces/'+encodeURIComponent(x.id),{method:'DELETE',headers:{'x-admin-key':$('cle').value}});charger();};
    d.append(b,s,document.createElement('br'),k);l.appendChild(d);}
}
if($('cle').value)charger();
</script>
</body>
</html>
''';
