#!/usr/bin/env python3
# ============================================================================
# FAKE PEER — simulateur de pair Droplet pour tester le mesh sans 2e téléphone
# ----------------------------------------------------------------------------
# Se connecte à l'app Droplet via le transport LocalWifi (TCP) et joue le rôle
# d'un vrai pair du protocole mesh :
#
#   - découverte : écoute le beacon UDP (port 42069) diffusé par l'app, en
#     récupère l'IP + le port TCP du serveur LocalWifi ;
#   - poignée de main : envoie/reçoit {peerId, pseudo} ;
#   - échange de clés : envoie son hello (clé publique X25519) et lit celui
#     de l'app → clé partagée dérivée (X25519 + HKDF) identique à l'app ;
#   - tests : message texte diffusé (clair), message texte chiffré (E2EE),
#     transfert de fichier, signalisation d'appel (offer + hangup), et
#     décodage de ce que l'app nous renvoie (hello, ACK, messages, appels).
#
# Protocole wire (reprend exactement le code de l'app) :
#   TCP : [4 octets BE = longueur][payload]
#   payload : [hopCount 1][type 1][json]
#   enveloppe json : {"c","s","r","m","t","e","n","k","ef","g","ctr"}
#   hello : {"c": pubkey_b64, "s": mon_id, "k": "hello"}
#   ACK   : [0][0x04]["id1,id2"]   (hopCount=0)
#   fichier : [hop][0x30][lenMeta 2][meta][lenNonce 1][nonce][payload]
#   appel : [0][0x10..0x13][json]  (jamais relayé)
#
# Usage :
#   python3 tools/fake_peer.py                 # suite de tests automatique
#   python3 tools/fake_peer.py --interactive   # REPL pour envoyer à la main
#   python3 tools/fake_peer.py --target 192.168.1.20   # skip la découverte UDP
# ============================================================================

import argparse
import base64
import hashlib
import json
import os
import socket
import struct
import sys
import time
import uuid

from cryptography.hazmat.primitives.asymmetric import x25519
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

# ---------------------------------------------------------------------------
# Constantes du protocole (identiques à lib/core/services/ble_mesh_protocol.dart)
# ---------------------------------------------------------------------------
DISCOVERY_PORT = 42069
K_TEXT = 0x01
K_TYPING = 0x02
K_TYPING_STOP = 0x03
K_ACK = 0x04
K_HELLO_KIND = "hello"
K_CALL_OFFER = 0x10
K_CALL_ANSWER = 0x11
K_CALL_ICE = 0x12
K_CALL_HANGUP = 0x13
K_FILE_TRANSFER = 0x30
DEFAULT_HOP_COUNT = 5

HKDF_INFO = b"droplet-1to1-v1"
HKDF_SALT = b"droplet-mesh"

FAKE_ID = "fake-peer-" + uuid.uuid4().hex[:12]
FAKE_PSEUDO = "PairSimule"


def derive_shared_key(my_private: x25519.X25519PrivateKey, peer_public_b64: str) -> bytes:
    """Reproduit CryptoService.sharedKeyWithPeer : X25519 puis HKDF-SHA256."""
    peer_pub = x25519.X25519PublicKey.from_public_bytes(base64.b64decode(peer_public_b64))
    shared = my_private.exchange(peer_pub)
    hkdf = HKDF(algorithm=hashes.SHA256(), length=32, salt=HKDF_SALT, info=HKDF_INFO)
    return hkdf.derive(shared)


def aes_gcm_encrypt(key: bytes, plaintext: bytes) -> (bytes, bytes):
    nonce = os.urandom(12)
    ct = AESGCM(key).encrypt(nonce, plaintext, None)
    return ct, nonce


def aes_gcm_decrypt(key: bytes, combined: bytes, nonce: bytes) -> bytes:
    return AESGCM(key).decrypt(nonce, combined, None)


def wrap(hop: int, msg_type: int, json_obj: dict) -> bytes:
    """Construit un payload wire [hop][type][json]."""
    payload = json.dumps(json_obj).encode()
    return bytes([hop, msg_type]) + payload


class FakePeer:
    def __init__(self, target_ip=None, target_port=None, filter_ip=None):
        self.private_key = x25519.X25519PrivateKey.generate()
        pub_raw = self.private_key.public_key().public_bytes(
            serialization.Encoding.Raw, serialization.PublicFormat.Raw)
        self.public_b64 = base64.b64encode(pub_raw).decode()
        self.sock = None
        self.app_id = None
        self.app_pseudo = None
        self.app_public_b64 = None
        self.shared_key = None
        self.pending_acks = {}   # id -> message d'origine (pour log)
        self.stats = {"tx": 0, "rx": 0, "acks_envoyes": 0, "acks_recus": 0}
        self.dump = False
        self._filter_ip = filter_ip
        if target_ip is not None:
            self._connect(target_ip, target_port)
        else:
            self._discover_and_connect()

    # -- Découverte ----------------------------------------------------------

    def _discover_and_connect(self):
        print(f"[*] Écoute du beacon UDP {DISCOVERY_PORT} pour trouver l'app…"
              + (f" (filtré IP {self._filter_ip})" if self._filter_ip else ""))
        udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        udp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        udp.bind(("", DISCOVERY_PORT))
        udp.settimeout(45)
        deadline = time.time() + 45
        while time.time() < deadline:
            try:
                data, addr = udp.recvfrom(1024)
            except socket.timeout:
                print("[!] Aucun beacon reçu — l'app est-elle allumée sur le même Wi-Fi ?")
                sys.exit(1)
            try:
                msg = json.loads(data.decode())
            except Exception:
                continue
            pid = msg.get("peerId")
            if not pid or pid == FAKE_ID:
                continue
            port = msg.get("port")
            if not port:
                continue
            if self._filter_ip and addr[0] != self._filter_ip:
                continue
            self.app_pseudo = msg.get("pseudo", pid)
            print(f"[+] Beacon reçu de {self.app_pseudo} ({addr[0]}:{port})")
            self._connect(addr[0], port)
            return

    def _connect(self, ip, port):
        print(f"[*] Connexion TCP à {ip}:{port}…")
        self.sock = socket.create_connection((ip, port), timeout=15)
        self.sock.settimeout(0.2)  # lecture non bloquante pour la boucle
        self._send_frame(json.dumps({"peerId": FAKE_ID, "pseudo": FAKE_PSEUDO}).encode())
        print("[+] Poignée de main envoyée — je suis", FAKE_PSEUDO, f"({FAKE_ID[:16]}…)")

    # -- I/O TCP -------------------------------------------------------------

    def _send_frame(self, payload: bytes):
        self.sock.sendall(struct.pack(">I", len(payload)) + payload)

    def send(self, hop: int, msg_type: int, json_obj: dict):
        frame = wrap(hop, msg_type, json_obj)
        self._send_frame(frame)
        self.stats["tx"] += 1
        return frame

    def send_raw(self, payload: bytes):
        self._send_frame(payload)
        self.stats["tx"] += 1

    def send_ack(self, message_id: str):
        self.send_raw(bytes([0, K_ACK]) + message_id.encode())
        self.stats["acks_envoyes"] += 1

    def send_hello(self):
        self.send(DEFAULT_HOP_COUNT, K_TEXT, {"c": self.public_b64, "s": FAKE_ID, "k": K_HELLO_KIND})
        print("[*] Hello envoyé (clé publique X25519)")

    def _recv_frame(self):
        """Retourne un payload complet (ou None si rien de prêt)."""
        if self.sock is None:
            return None
        try:
            header = self.sock.recv(4)
        except socket.timeout:
            return None
        except OSError:
            return None
        if not header:
            return None
        if len(header) < 4:
            return None
        length = struct.unpack(">I", header)[0]
        payload = b""
        while len(payload) < length:
            chunk = self.sock.recv(length - len(payload))
            if not chunk:
                return None
            payload += chunk
        return payload

    # -- Traitement ----------------------------------------------------------

    def process(self, payload: bytes):
        self.stats["rx"] += 1
        if self.dump:
            print(f"[RAW] len={len(payload)} hex={payload.hex()}")
        if len(payload) < 2:
            return
        hop, msg_type = payload[0], payload[1]
        body = payload[2:]

        if msg_type == K_ACK:
            ids = body.decode(errors="replace").split(",")
            for i in ids:
                if i in self.pending_acks:
                    orig = self.pending_acks.pop(i)
                    print(f"[✓] ACK de l'app pour «{orig}» ({i[:16]}…)")
                else:
                    print(f"[✓] ACK de l'app pour {i[:16]}…")
            self.stats["acks_recus"] += 1
            return

        if K_CALL_OFFER <= msg_type <= K_CALL_HANGUP:
            return self._handle_call(msg_type, body)

        if msg_type != K_TEXT:
            print(f"[-] Type inconnu 0x{msg_type:02x} (hop={hop}) ignoré")
            return

        # hello / texte / frappe — tous en json
        try:
            obj = json.loads(body.decode())
        except Exception:
            print(f"[-] JSON illisible ({len(body)}o) ignoré")
            return

        kind = obj.get("k")
        sender = obj.get("s")
        target = obj.get("t")
        app_msg_id = obj.get("m")

        if kind == K_HELLO_KIND:
            if sender and sender != FAKE_ID and self.app_id is None:
                self.app_id = sender
                self.app_public_b64 = obj.get("c")
                print(f"[+] Hello de l'app : id={sender[:16]}… clé publique reçue")
                if self.app_public_b64:
                    self.shared_key = derive_shared_key(self.private_key, self.app_public_b64)
                    print("[+] Clé partagée dérivée (X25519 + HKDF) — E2EE prêt")
            return

        if kind == "typing":
            print(f"[…] {sender[:12]}… est en train d'écrire")
            return

        encrypted = bool(obj.get("e"))
        content = obj.get("c")
        if encrypted and sender and self.shared_key:
            try:
                plain = aes_gcm_decrypt(self.shared_key, base64.b64decode(content),
                                        base64.b64decode(obj.get("n", "")))
                content = plain.decode()
            except Exception as e:
                content = f"<déchiffrement échoué: {e}>"
                print("[!] Échec déchiffrement E2EE")
        elif encrypted:
            content = "<chiffré mais pas de clé>"

        print(f"[←] {'CHIFFRÉ' if encrypted else 'clair'} de {sender or '?'}: {content}")
        if app_msg_id:
            self.send_ack(app_msg_id)
        elif msg_type == K_TEXT and not encrypted and target is None:
            # message diffusé sans id : on n'ACK pas (rien à accuser)
            pass

    def _handle_call(self, msg_type, body):
        try:
            obj = json.loads(body.decode())
        except Exception:
            obj = {}
        labels = {K_CALL_OFFER: "OFFRE", K_CALL_ANSWER: "RÉPONSE",
                  K_CALL_ICE: "ICE", K_CALL_HANGUP: "RACCROCHE"}
        print(f"[☎] Signalisation {labels.get(msg_type, hex(msg_type))} : {list(obj.keys())}")
        if msg_type == K_CALL_OFFER:
            # Répondre comme un vrai pair : answer + hangup (pas de média réel)
            self.send(0, K_CALL_ANSWER, {"sdp": "v=0\nfake-answer"})
            self.send(0, K_CALL_HANGUP, {})
            print("[☎] Réponse simulée (answer + hangup) envoyée")

    # -- Envois de test ------------------------------------------------------

    def test_broadcast_text(self, text="Salut depuis le faux pair !"):
        mid = f"txt-{uuid.uuid4().hex[:10]}"
        self.pending_acks[mid] = text
        self.send(DEFAULT_HOP_COUNT, K_TEXT, {"c": text, "s": FAKE_ID, "m": mid})
        print(f"[→] Message diffusé envoyé : «{text}»")

    def test_encrypted_text(self, text="Message chiffré de bout en bout (E2EE) !"):
        if not self.shared_key:
            print("[!] Pas de clé partagée — impossible de chiffrer")
            return
        mid = f"enc-{uuid.uuid4().hex[:10]}"
        cipher, nonce = aes_gcm_encrypt(self.shared_key, text.encode())
        self.pending_acks[mid] = f"<chiffré> {text}"
        self.send(DEFAULT_HOP_COUNT, K_TEXT, {
            "c": base64.b64encode(cipher).decode(),
            "s": FAKE_ID,
            "m": mid,
            "t": self.app_id,
            "e": True,
            "n": base64.b64encode(nonce).decode(),
        })
        print(f"[→] Message E2EE envoyé à l'app : «{text}»")

    def test_file_transfer(self, name="bonjour-du-fake.txt",
                           mime="text/plain", content=b"Contenu de fichier simule!\n"):
        file_id = f"file-{uuid.uuid4().hex[:10]}"
        meta = {"fileId": file_id, "s": FAKE_ID, "e": False}
        meta_bytes = json.dumps(meta).encode()
        inner = (struct.pack(">H", len(name.encode())) + name.encode()
                 + bytes([len(mime.encode())]) + mime.encode() + content)
        payload = (bytes([DEFAULT_HOP_COUNT, K_FILE_TRANSFER])
                   + struct.pack(">H", len(meta_bytes)) + meta_bytes
                   + bytes([0]) + inner)
        self.pending_acks[file_id] = f"fichier {name}"
        self.send_raw(payload)
        print(f"[→] Transfert de fichier envoyé : {name} ({len(content)}o) id={file_id[:16]}…")

    def test_call(self):
        self.send(0, K_CALL_OFFER, {"sdp": "v=0\r\no=- 1 1 IN IP4 0.0.0.0\r\ns=fake-offer\r\n",
                                    "participants": None})
        print("[→] Offre d'appel envoyée (signaling)")
        time.sleep(1.0)
        self.send(0, K_CALL_HANGUP, {})
        print("[→] Raccrochage envoyé")

    def test_status(self, content="Statut du faux pair"):
        """Envoie un statut (même format que sendStatus dans mesh_repository.dart)."""
        status_id = f"status-{uuid.uuid4().hex[:10]}"
        now = time.strftime("%Y-%m-%dT%H:%M:%S")
        payload = {
            "id": status_id,
            "content": content,
            "createdAt": now,
            "expiresAt": "2099-01-01T00:00:00",
        }
        self.send(DEFAULT_HOP_COUNT, K_TEXT, {
            "c": json.dumps(payload),
            "s": FAKE_ID,
            "k": "status",
        })
        print(f"[→] Statut diffusé : «{content}» id={status_id[:16]}…")

    def test_safety_checkin(self, lat=None, lon=None):
        """Envoie un check-in de sécurité (même format que sendSafetyCheckin)."""
        now = time.strftime("%Y-%m-%dT%H:%M:%S")
        payload = {
            "status": "safe",
            "ts": now,
        }
        if lat is not None:
            payload["lat"] = round(lat, 2)
        if lon is not None:
            payload["lon"] = round(lon, 2)
        self.send(DEFAULT_HOP_COUNT, K_TEXT, {
            "c": json.dumps(payload),
            "s": FAKE_ID,
            "k": "safety_checkin",
        })
        print(f"[→] Check-in sécurité diffusé (lat={lat}, lon={lon})")

    def test_position(self, lat=48.8566, lon=2.3522):
        """Envoie une position géolocalisation."""
        self.send(DEFAULT_HOP_COUNT, K_TEXT, {
            "c": json.dumps({"lat": lat, "lon": lon, "ts": time.strftime("%Y-%m-%dT%H:%M:%S")}),
            "s": FAKE_ID,
            "k": "location",
        })
        print(f"[→] Position envoyée : {lat}, {lon}")

    def test_image_file(self, name="photo-test.jpg", size_kb=50):
        """Envoie un fichier image simulé via kFileTransferType."""
        content = bytes(range(256)) * (size_kb * 1024 // 256)
        self.test_file_transfer(name=name, mime="image/jpeg", content=content)

    def test_video_file(self, name="video-test.mp4", size_kb=200):
        """Envoie un fichier vidéo simulé via kFileTransferType."""
        content = bytes(range(256)) * (size_kb * 1024 // 256)
        self.test_file_transfer(name=name, mime="video/mp4", content=content)

    # -- Boucle --------------------------------------------------------------

    def run(self, duration):
        deadline = time.time() + duration
        while time.time() < deadline:
            payload = self._recv_frame()
            if payload:
                self.process(payload)
            else:
                time.sleep(0.05)
        self._print_stats()

    def _print_stats(self):
        print("\n" + "=" * 50)
        print("RÉSUMÉ DES ÉCHANGES")
        print(f"  trames envoyées : {self.stats['tx']}")
        print(f"  trames reçues   : {self.stats['rx']}")
        print(f"  ACK envoyés     : {self.stats['acks_envoyes']}")
        print(f"  ACK reçus       : {self.stats['acks_recus']}")
        print(f"  clé partagée    : {'OK (E2EE opérationnel)' if self.shared_key else 'ABSENTE'}")
        print("=" * 50)


def run_tests(peer: FakePeer):
    def drain(seconds):
        end = time.time() + seconds
        while time.time() < end:
            p = peer._recv_frame()
            if p:
                peer.process(p)
            else:
                time.sleep(0.05)

    drain(1.5)
    peer.send_hello()
    drain(1.0)
    peer.test_broadcast_text()
    drain(2.0)
    if peer.app_id and peer.shared_key:
        peer.test_encrypted_text()
    else:
        print("[!] Pas d'id/clé app — E2EE sauté")
    drain(2.0)
    peer.test_status()
    drain(2.0)
    peer.test_safety_checkin(48.8566, 2.3522)
    drain(2.0)
    peer.test_position(48.8566, 2.3522)
    drain(2.0)
    peer.test_file_transfer()
    drain(2.0)
    peer.test_image_file()
    drain(2.0)
    peer.test_video_file()
    drain(2.0)
    peer.test_call()
    print("\n[*] Tests envoyés (texte, E2EE, statut, sécurité, position, fichier, image, vidéo, appel).")
    print("    Écoute des réponses 12 s…")
    peer.run(12)


def interactive(peer: FakePeer):
    print("\nREPL — commandes :")
    print("  hello              envoie l'échange de clés")
    print("  text <msg>         message diffusé (clair)")
    print("  enc <msg>          message chiffré E2EE vers l'app")
    print("  status <msg>       statut diffusé")
    print("  safety [lat] [lon]  check-in sécurité")
    print("  position [lat] [lon] position géolocalisation")
    print("  file               transfert de fichier texte")
    print("  image [size_kb]    fichier image simulé")
    print("  video [size_kb]    fichier vidéo simulé")
    print("  call               offre d'appel + raccrochage")
    print("  quit               quitter")
    while True:
        try:
            line = input("fake> ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if not line:
            continue
        parts = line.split(" ", 1)
        cmd = parts[0]
        arg = parts[1] if len(parts) > 1 else ""
        if cmd == "hello":
            peer.send_hello()
        elif cmd == "text":
            peer.test_broadcast_text(arg or "Coucou depuis le faux pair !")
        elif cmd == "enc":
            peer.test_encrypted_text(arg or "Message E2EE de test !")
        elif cmd == "status":
            peer.test_status(arg or "Statut du faux pair")
        elif cmd == "safety":
            parts2 = arg.split()
            lat = float(parts2[0]) if len(parts2) > 0 else 48.8566
            lon = float(parts2[1]) if len(parts2) > 1 else 2.3522
            peer.test_safety_checkin(lat, lon)
        elif cmd == "position":
            parts2 = arg.split()
            lat = float(parts2[0]) if len(parts2) > 0 else 48.8566
            lon = float(parts2[1]) if len(parts2) > 1 else 2.3522
            peer.test_position(lat, lon)
        elif cmd == "file":
            peer.test_file_transfer()
        elif cmd == "image":
            size = int(arg) if arg else 50
            peer.test_image_file(size_kb=size)
        elif cmd == "video":
            size = int(arg) if arg else 200
            peer.test_video_file(size_kb=size)
        elif cmd == "call":
            peer.test_call()
        elif cmd == "quit":
            break
        else:
            print("commande inconnue")
        # drain ce qui arrive rapidement après une commande
        end = time.time() + 1.5
        while time.time() < end:
            p = peer._recv_frame()
            if p:
                peer.process(p)
            else:
                time.sleep(0.05)


def main():
    ap = argparse.ArgumentParser(description="Faux pair Droplet (test mesh via LocalWifi)")
    ap.add_argument("--interactive", action="store_true", help="REPL au lieu de la suite automatique")
    ap.add_argument("--call", action="store_true", help="n'envoie que le test d'appel (offer + réponse + hangup)")
    ap.add_argument("--target", help="IP de l'app (saute la découverte UDP)")
    ap.add_argument("--port", type=int, default=0, help="port TCP de l'app (avec --target)")
    ap.add_argument("--filter-ip", help="IP du beacon à choisir (ignorer les autres)")
    ap.add_argument("--dump", action="store_true", help="affiche les trames brutes (hex + json)")
    args = ap.parse_args()

    peer = FakePeer(target_ip=args.target, target_port=args.port or None,
                    filter_ip=args.filter_ip)
    if args.dump:
        print("[*] Mode dump : trames brutes affichées pendant la suite de tests")
        peer.dump = True
    if args.call:
        print("[*] Mode appel : offer + écoute, réponse, hangup…")
        peer.send(0, K_CALL_OFFER, {"sdp": "v=0\r\no=- 1 1 IN IP4 0.0.0.0\r\ns=fake-offer\r\n",
                                    "participants": None})
        peer.run(4)
        peer.send(0, K_CALL_HANGUP, {})
        print("[→] Raccrochage envoyé")
        peer.run(3)
        return
    if args.interactive:
        interactive(peer)
    else:
        run_tests(peer)


if __name__ == "__main__":
    main()
