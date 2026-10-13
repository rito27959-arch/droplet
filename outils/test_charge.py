# Test de charge de la boîte aux lettres (machine GitHub : 4 cœurs, comme un petit serveur).
# N appareils en attente longue + des expéditeurs qui déposent en continu.
import asyncio, json, os, random, statistics, sys, time
import aiohttp
BOI = 'http://127.0.0.1:8081'
N = int(sys.argv[1]); DEPOTS_S = int(sys.argv[2]); DUREE = int(sys.argv[3])
recus, latences, erreurs, depots = 0, [], 0, 0
envoi = {}
async def appareil(s, i):
    global recus, erreurs
    pid = f'appareil{i:06d}'
    ip = {'X-Real-IP': f'10.{i // 65536}.{(i // 256) % 256}.{i % 256}'}  # un téléphone = une adresse
    fin = time.time() + DUREE
    await asyncio.sleep(random.random() * 3)
    while time.time() < fin:
        try:
            async with s.get(f'{BOI}/messages/{pid}?attendre=20', headers=ip) as r:
                if r.status != 200: erreurs += 1; await asyncio.sleep(1); continue
                j = await r.json()
            for m in j['messages']:
                recus += 1
                t = envoi.pop(m['payload'], None)
                if t: latences.append(time.time() - t)
                async with s.delete(f"{BOI}/messages/{pid}/{m['id']}", headers=ip) as d: pass
        except Exception:
            erreurs += 1; await asyncio.sleep(1)
async def expediteurs(s):
    fin = time.time() + DUREE - 5
    await asyncio.sleep(4)
    while time.time() < fin:
        t0 = time.time()
        async def un():
            global depots, erreurs
            p = f'p{random.random()}'; envoi[p] = time.time()
            try:
                async with s.post(f'{BOI}/messages', headers={'X-Real-IP': f'172.16.{random.randrange(256)}.{random.randrange(256)}'}, json={'from': f'exp{random.randint(0,99999):05d}', 'to': f'appareil{random.randrange(N):06d}', 'payload': p}) as r:
                    if r.status == 200: depots += 1
                    else: erreurs += 1
            except Exception: erreurs += 1
        await asyncio.gather(*[un() for _ in range(DEPOTS_S)])
        await asyncio.sleep(max(0, 1 - (time.time() - t0)))
mesures = []
async def surveiller():
    # Processeur et mémoire de la boîte, relevés toutes les 2 s pendant le test.
    import subprocess
    pid = subprocess.run(['pgrep', '-f', '/tmp/boite'], capture_output=True, text=True).stdout.split()[0]
    tic = os.sysconf('SC_CLK_TCK'); avant = None
    fin = time.time() + DUREE
    while time.time() < fin:
        st = open(f'/proc/{pid}/stat').read().rsplit(')', 1)[1].split()
        cpu = (int(st[11]) + int(st[12])) / tic
        rss = int(open(f'/proc/{pid}/status').read().split('VmRSS:')[1].split()[0]) // 1024
        if avant: mesures.append(((cpu - avant[0]) / (time.time() - avant[1]) * 100, rss))
        avant = (cpu, time.time())
        await asyncio.sleep(2)
async def main():
    con = aiohttp.TCPConnector(limit=0)
    async with aiohttp.ClientSession(connector=con, timeout=aiohttp.ClientTimeout(total=60)) as s:
        await asyncio.gather(surveiller(), expediteurs(s), *[appareil(s, i) for i in range(N)])
    l = sorted(latences)
    print(f"appareils connectés en attente longue : {N}")
    print(f"dépôts réussis : {depots} ({depots/(DUREE-9):.0f}/s, visé {DEPOTS_S}/s) · reçus : {recus} · erreurs : {erreurs}")
    if l: print(f"délai dépôt → réception : médiane {statistics.median(l)*1000:.0f} ms · 95 % {l[int(len(l)*.95)]*1000:.0f} ms · max {l[-1]*1000:.0f} ms")
    if mesures: print(f"boîte : processeur max {max(m[0] for m in mesures):.0f} % (moyenne {statistics.mean(m[0] for m in mesures):.0f} %, 100 % = 1 cœur) · mémoire max {max(m[1] for m in mesures)} Mo")
asyncio.run(main())
