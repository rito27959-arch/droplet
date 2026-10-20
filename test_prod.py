import base64, hashlib, hmac, json, os, time, urllib.request, sys
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey, X25519PublicKey
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes, serialization
ANN='https://droplet-directory-production.up.railway.app'; BOI='https://droplet-mailbox-production.up.railway.app'
SRV=X25519PublicKey.from_public_bytes(base64.b64decode('neYh3XycaSQiYriTFKq0auqa6gdcvfVkhfP0Ocg9unI='))
cle=X25519PrivateKey.generate(); pub=base64.b64encode(cle.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)).decode()
pid=hashlib.sha256(('diag'+str(time.time())).encode()).hexdigest()
k=HKDF(hashes.SHA256(),32,salt=b'droplet-mesh',info=b'droplet-auth-v1').derive(cle.exchange(SRV))
def sig(m,ch,corps=b'',decal=0):
    ts=str(int(time.time())+decal); n=base64.urlsafe_b64encode(os.urandom(16)).decode().rstrip('=')
    c=f"{m}\n{ch}\n{ts}\n{n}\n{hashlib.sha256(corps).hexdigest()}"
    return {'x-droplet-id':pid,'x-droplet-ts':ts,'x-droplet-nonce':n,'x-droplet-sig':base64.urlsafe_b64encode(hmac.new(k,c.encode(),hashlib.sha256).digest()).decode().rstrip('=')}
def req(url,m='GET',corps=None,e=None):
    r=urllib.request.Request(url,method=m,data=corps,headers={'content-type':'application/json',**(e or {})})
    try:
        with urllib.request.urlopen(r,timeout=30) as x: return x.status,dict(x.headers),x.read().decode()
    except urllib.error.HTTPError as er: return er.code,dict(er.headers),er.read().decode()
b=json.dumps({'peerId':pid,'pseudo':'Diagnostic','onion':'x.onion','publicKey':pub}).encode()
s,h,c=req(ANN+'/register','POST',b,sig('POST','/register',b)); print('inscription signée (neuf):',s,c[:80])
s,h,c=req(BOI+'/messages/'+pid,e=sig('GET','/messages/'+pid)); print('relève boîte:',s,c[:60])
s,h,c=req(BOI+'/messages/'+pid,e=sig('GET','/messages/'+pid,decal=900)); print('horloge +15 min:',s,h.get('x-droplet-raison') or h.get('X-Droplet-Raison'),c[:80])
bd=json.dumps({'peerId':pid}).encode()
s,h,c=req(ANN+'/register','DELETE',bd,sig('DELETE','/register',bd)); print('désinscription:',s)
