# Test de charge de la boîte aux lettres (machine GitHub : 4 cœurs, partagés
# entre le serveur ET ce client — le serveur réel aura les siens).
# N appareils en attente longue + des expéditeurs qui déposent en continu.
# Le client tourne sur plusieurs processus pour ne pas être le goulot.
import asyncio, multiprocessing as mp, os, random, statistics, subprocess, sys, time
import aiohttp
BOI = 'http://127.0.0.1:8081'
N = int(sys.argv[1]); DEPOTS_S = int(sys.argv[2]); DUREE = int(sys.argv[3])
P = 3  # processus clients


def travailleur(k, sortie):
    mes = range(k, N, P)  # les appareils de ce processus
    st = {'recus': 0, 'erreurs': 0, 'depots': 0, 'latences': []}
    envoi = {}

    async def appareil(s, i):
        pid = f'appareil{i:06d}'
        ip = {'X-Real-IP': f'10.{i // 65536}.{(i // 256) % 256}.{i % 256}'}  # un téléphone = une adresse
        fin = time.time() + DUREE
        await asyncio.sleep(random.random() * 3)
        while time.time() < fin:
            try:
                async with s.get(f'{BOI}/messages/{pid}?attendre=20', headers=ip) as r:
                    if r.status != 200:
                        st['erreurs'] += 1; await asyncio.sleep(1); continue
                    j = await r.json()
                for m in j['messages']:
                    st['recus'] += 1
                    t = envoi.pop(m['payload'], None)
                    if t: st['latences'].append(time.time() - t)
                    async with s.delete(f"{BOI}/messages/{pid}/{m['id']}", headers=ip) as d: pass
            except Exception:
                st['erreurs'] += 1; await asyncio.sleep(1)

    async def expediteurs(s):
        fin = time.time() + DUREE - 5
        part = max(1, DEPOTS_S // P)
        await asyncio.sleep(4)
        while time.time() < fin:
            t0 = time.time()
            async def un():
                p = f'p{random.random()}'; envoi[p] = time.time()
                try:
                    async with s.post(f'{BOI}/messages',
                                      headers={'X-Real-IP': f'172.16.{random.randrange(256)}.{random.randrange(256)}'},
                                      json={'from': f'exp{random.randint(0, 99999):05d}', 'to': f'appareil{random.choice(mes):06d}', 'payload': p}) as r:
                        if r.status == 200: st['depots'] += 1
                        else: st['erreurs'] += 1
                except Exception: st['erreurs'] += 1
            await asyncio.gather(*[un() for _ in range(part)])
            await asyncio.sleep(max(0, 1 - (time.time() - t0)))

    async def principal():
        con = aiohttp.TCPConnector(limit=0)
        async with aiohttp.ClientSession(connector=con, timeout=aiohttp.ClientTimeout(total=60)) as s:
            await asyncio.gather(expediteurs(s), *[appareil(s, i) for i in mes])

    asyncio.run(principal())
    sortie.put(st)


def surveiller(fin, mesures):
    # Processeur et mémoire de la boîte (toutes ses copies), toutes les 2 s.
    pid = subprocess.run(['pgrep', '-f', '/tmp/boite'], capture_output=True, text=True).stdout.split()[0]
    tic = os.sysconf('SC_CLK_TCK'); avant = None
    while time.time() < fin:
        st = open(f'/proc/{pid}/stat').read().rsplit(')', 1)[1].split()
        cpu = (int(st[11]) + int(st[12])) / tic
        rss = int(open(f'/proc/{pid}/status').read().split('VmRSS:')[1].split()[0]) // 1024
        if avant: mesures.append(((cpu - avant[0]) / (time.time() - avant[1]) * 100, rss))
        avant = (cpu, time.time())
        time.sleep(2)


if __name__ == '__main__':
    sortie = mp.Queue()
    procs = [mp.Process(target=travailleur, args=(k, sortie)) for k in range(P)]
    for p in procs: p.start()
    mesures = []
    surveiller(time.time() + DUREE, mesures)
    res = [sortie.get() for _ in procs]
    for p in procs: p.join()
    depots = sum(r['depots'] for r in res); recus = sum(r['recus'] for r in res); erreurs = sum(r['erreurs'] for r in res)
    l = sorted(x for r in res for x in r['latences'])
    print(f"appareils connectés en attente longue : {N}")
    print(f"dépôts réussis : {depots} ({depots / (DUREE - 9):.0f}/s, visé {DEPOTS_S}/s) · reçus : {recus} · erreurs : {erreurs}")
    if l: print(f"délai dépôt → réception : médiane {statistics.median(l) * 1000:.0f} ms · 95 % {l[int(len(l) * .95)] * 1000:.0f} ms · max {l[-1] * 1000:.0f} ms")
    if mesures: print(f"boîte : processeur max {max(m[0] for m in mesures):.0f} % (moyenne {statistics.mean(m[0] for m in mesures):.0f} %, 100 % = 1 cœur) · mémoire max {max(m[1] for m in mesures)} Mo")
