#!/usr/bin/env python3
# ============================================================================
# FAUX50.PY — TEST DE TRANSPORT FICHIER 50 MiB POUR DROPLET
#
# Reprend le framing TCP et le format FILE_TRANSFER (0x30) visible
# dans fake_peer.py.
#
# ATTENTION :
# - Cette version ne prétend PAS connaître une fragmentation applicative
#   qui n'est pas présente dans le code fourni.
# - Les 50 MiB sont envoyés à travers une seule frame TCP.
# - Le contenu est généré progressivement.
# - sendall() n'a pas de timeout artificiel de 1 seconde.
# - SHA-256 est calculé avant l'envoi.
#
# Pour implémenter la vraie fragmentation/ACK/reprise de Droplet,
# il faudra utiliser le code Dart qui traite K_FILE_TRANSFER / 0x30.
# ============================================================================

import base64
import hashlib
import json
import socket
import struct
import sys
import time
import uuid


# ============================================================================
# CONSTANTES
# ============================================================================

DISCOVERY_PORT = 42069

K_TEXT = 0x01
K_ACK = 0x04
K_FILE_TRANSFER = 0x30

DEFAULT_HOP_COUNT = 5

FILE_SIZE = 50 * 1024 * 1024
FILE_NAME = "test-50mb.bin"
FILE_MIME = "application/octet-stream"

FAKE_ID = "fake-peer-50mb-" + uuid.uuid4().hex[:12]
FAKE_PSEUDO = "Fake50MB"

SEND_BUFFER = 1024 * 1024


# ============================================================================
# FAKE PEER
# ============================================================================

class FakePeer:

    def __init__(self, target_ip=None, target_port=None):

        self.sock = None

        self.app_id = None
        self.app_pseudo = None

        self.file_id = (
            "file-" +
            uuid.uuid4().hex[:12]
        )

        self.stats = {
            "frames_tx": 0,
            "frames_rx": 0,
            "acks_rx": 0,
            "bytes_tx": 0,
        }

        if target_ip:

            self.connect(
                target_ip,
                target_port
            )

        else:

            self.discover()

    # ========================================================================
    # DISCOVERY
    # ========================================================================

    def discover(self):

        print(
            f"[*] Écoute du beacon UDP "
            f"{DISCOVERY_PORT}..."
        )

        udp = socket.socket(
            socket.AF_INET,
            socket.SOCK_DGRAM
        )

        udp.setsockopt(
            socket.SOL_SOCKET,
            socket.SO_REUSEADDR,
            1
        )

        udp.bind(
            ("", DISCOVERY_PORT)
        )

        udp.settimeout(1)

        deadline = time.monotonic() + 30

        while time.monotonic() < deadline:

            try:

                data, addr = udp.recvfrom(
                    4096
                )

            except socket.timeout:

                continue

            try:

                beacon = json.loads(
                    data.decode()
                )

            except Exception:

                continue

            peer_id = beacon.get(
                "peerId"
            )

            port = beacon.get(
                "port"
            )

            if not peer_id or not port:
                continue

            if peer_id == FAKE_ID:
                continue

            self.app_id = peer_id

            self.app_pseudo = beacon.get(
                "pseudo",
                peer_id
            )

            print(
                f"[+] Beacon reçu de "
                f"{self.app_pseudo} "
                f"({addr[0]}:{port})"
            )

            udp.close()

            self.connect(
                addr[0],
                int(port)
            )

            return

        udp.close()

        raise RuntimeError(
            "Aucun beacon Droplet reçu."
        )

    # ========================================================================
    # TCP
    # ========================================================================

    def connect(self, ip, port):

        print(
            f"[*] Connexion TCP "
            f"{ip}:{port}..."
        )

        self.sock = socket.create_connection(
            (ip, port),
            timeout=15
        )

        # IMPORTANT :
        # On ne met PAS 1 seconde ici.
        #
        # 50 MiB peuvent prendre plusieurs secondes à travers
        # le buffer TCP/Wi-Fi.
        self.sock.settimeout(None)

        # Augmente le buffer d'émission lorsque possible.
        try:

            self.sock.setsockopt(
                socket.SOL_SOCKET,
                socket.SO_SNDBUF,
                4 * 1024 * 1024
            )

        except OSError:

            pass

        handshake = json.dumps({
            "peerId": FAKE_ID,
            "pseudo": FAKE_PSEUDO,
        }).encode()

        self.send_frame(
            handshake
        )

        print(
            "[+] Poignée de main envoyée"
        )

    # ========================================================================
    # FRAME TCP
    # ========================================================================

    def send_frame(self, payload):

        frame_len = len(payload)

        self.sock.sendall(
            struct.pack(
                ">I",
                frame_len
            )
        )

        self.sock.sendall(
            payload
        )

        self.stats["frames_tx"] += 1
        self.stats["bytes_tx"] += frame_len

    # ========================================================================
    # HELLO
    # ========================================================================

    def send_hello(self):

        hello = {
            "c": "",
            "s": FAKE_ID,
            "k": "hello",
        }

        payload = (
            bytes([
                DEFAULT_HOP_COUNT,
                K_TEXT,
            ])
            +
            json.dumps(
                hello,
                separators=(",", ":")
            ).encode()
        )

        self.send_frame(
            payload
        )

        print(
            "[→] Hello envoyé"
        )

    # ========================================================================
    # GÉNÉRATION DU CONTENU
    # ========================================================================

    @staticmethod
    def generate_content(size):

        pattern = bytes(
            range(256)
        )

        remaining = size

        while remaining:

            block_size = min(
                remaining,
                SEND_BUFFER
            )

            block = (
                pattern *
                (
                    (block_size + 255)
                    // 256
                )
            )[:block_size]

            yield block

            remaining -= block_size

    # ========================================================================
    # SHA256
    # ========================================================================

    def calculate_sha256(self):

        print(
            "[*] Calcul du SHA-256..."
        )

        sha = hashlib.sha256()

        processed = 0

        for block in self.generate_content(
            FILE_SIZE
        ):

            sha.update(
                block
            )

            processed += len(block)

        digest = sha.hexdigest()

        print(
            f"[*] SHA-256 : {digest}"
        )

        return digest

    # ========================================================================
    # CONSTRUCTION DU PAYLOAD 0x30
    # ========================================================================

    def build_file_payload(self, sha256):

        filename = FILE_NAME.encode(
            "utf-8"
        )

        mime = FILE_MIME.encode(
            "utf-8"
        )

        metadata = {
            "fileId": self.file_id,
            "s": FAKE_ID,
            "e": False,

            # Métadonnées informatives.
            "size": FILE_SIZE,
            "sha256": sha256,
        }

        meta = json.dumps(
            metadata,
            separators=(",", ":")
        ).encode()

        if len(meta) > 65535:

            raise RuntimeError(
                "Metadata > 65535 octets"
            )

        if len(filename) > 65535:

            raise RuntimeError(
                "Nom de fichier trop long"
            )

        if len(mime) > 255:

            raise RuntimeError(
                "MIME > 255 octets"
            )

        # --------------------------------------------------------------------
        # Format visible dans ton fake_peer original :
        #
        # [hop]
        # [type 0x30]
        # [metaLen uint16 BE]
        # [metadata]
        # [nonceLen uint8]
        # [filenameLen uint16 BE]
        # [filename]
        # [mimeLen uint8]
        # [mime]
        # [content]
        # --------------------------------------------------------------------

        prefix = (
            bytes([
                DEFAULT_HOP_COUNT,
                K_FILE_TRANSFER,
            ])

            +

            struct.pack(
                ">H",
                len(meta)
            )

            +

            meta

            +

            bytes([
                0
            ])

            +

            struct.pack(
                ">H",
                len(filename)
            )

            +

            filename

            +

            bytes([
                len(mime)
            ])

            +

            mime
        )

        return prefix

    # ========================================================================
    # ENVOI 50 MiB
    # ========================================================================

    def send_50mb(self):

        print()
        print("=" * 64)
        print(
            "TEST 50 MiB — FILE_TRANSFER 0x30"
        )
        print("=" * 64)

        print(
            f"[*] fileId : {self.file_id}"
        )

        print(
            f"[*] Taille : "
            f"{FILE_SIZE:,} octets"
        )

        sha256 = self.calculate_sha256()

        prefix = self.build_file_payload(
            sha256
        )

        # Taille totale de la frame.
        payload_size = (
            len(prefix) +
            FILE_SIZE
        )

        print(
            f"[*] Header fichier : "
            f"{len(prefix):,} octets"
        )

        print(
            f"[*] Payload : "
            f"{payload_size:,} octets"
        )

        print(
            f"[*] Frame TCP : "
            f"{payload_size + 4:,} octets"
        )

        # --------------------------------------------------------------------
        # ATTENTION :
        # On ne construit PAS un énorme bytearray de 50 MiB.
        #
        # On écrit :
        #
        # [4 bytes longueur]
        # [prefix]
        # [contenu progressivement]
        #
        # Cela évite une deuxième copie mémoire inutile.
        # --------------------------------------------------------------------

        print()
        print(
            "[→] Envoi du header..."
        )

        start = time.monotonic()

        self.sock.sendall(
            struct.pack(
                ">I",
                payload_size
            )
        )

        self.sock.sendall(
            prefix
        )

        sent = 0

        last_print = 0

        sha_verify = hashlib.sha256()

        print(
            "[→] Envoi des données..."
        )

        for block in self.generate_content(
            FILE_SIZE
        ):

            self.sock.sendall(
                block
            )

            sha_verify.update(
                block
            )

            sent += len(block)

            now = time.monotonic()

            if (
                now - last_print >= 0.5
                or sent == FILE_SIZE
            ):

                elapsed = max(
                    now - start,
                    0.001
                )

                mib = sent / 1024 / 1024

                total_mib = (
                    FILE_SIZE /
                    1024 /
                    1024
                )

                speed = (
                    sent /
                    elapsed /
                    1024 /
                    1024
                )

                percent = (
                    sent /
                    FILE_SIZE *
                    100
                )

                print(
                    f"\r[→] "
                    f"{percent:6.2f}% "
                    f"{mib:6.2f}/{total_mib:.2f} MiB "
                    f"{speed:.2f} MiB/s",
                    end="",
                    flush=True
                )

                last_print = now

        print()

        elapsed = (
            time.monotonic() -
            start
        )

        real_speed = (
            FILE_SIZE /
            elapsed /
            1024 /
            1024
        )

        calculated = (
            sha_verify.hexdigest()
        )

        print()
        print(
            "[✓] 50 MiB envoyés au socket TCP"
        )

        print(
            f"    durée   : {elapsed:.2f}s"
        )

        print(
            f"    débit   : "
            f"{real_speed:.2f} MiB/s"
        )

        print(
            f"    SHA-256 : {calculated}"
        )

        if calculated != sha256:

            print(
                "[!] ERREUR : SHA-256 incohérent "
                "pendant la génération"
            )

            return False

        print(
            "[✓] SHA-256 source vérifié"
        )

        return True

    # ========================================================================
    # LECTURE DES RÉPONSES
    # ========================================================================

    def read_frame(self, timeout=5):

        old_timeout = self.sock.gettimeout()

        self.sock.settimeout(
            timeout
        )

        try:

            header = self._recv_exact(
                4
            )

            length = struct.unpack(
                ">I",
                header
            )[0]

            if length > 100 * 1024 * 1024:

                raise RuntimeError(
                    f"Frame reçue trop grande : "
                    f"{length:,}"
                )

            payload = self._recv_exact(
                length
            )

            self.stats["frames_rx"] += 1

            return payload

        finally:

            self.sock.settimeout(
                old_timeout
            )

    def _recv_exact(self, size):

        data = bytearray()

        while len(data) < size:

            chunk = self.sock.recv(
                size - len(data)
            )

            if not chunk:

                raise ConnectionError(
                    "Connexion fermée"
                )

            data.extend(
                chunk
            )

        return bytes(data)

    # ========================================================================
    # ATTENTE DES RÉPONSES
    # ========================================================================

    def listen(self, seconds=30):

        print()
        print(
            f"[*] Écoute des réponses "
            f"pendant {seconds}s..."
        )

        deadline = (
            time.monotonic() +
            seconds
        )

        while time.monotonic() < deadline:

            remaining = max(
                0.1,
                deadline -
                time.monotonic()
            )

            try:

                payload = self.read_frame(
                    min(
                        remaining,
                        1.0
                    )
                )

            except socket.timeout:

                continue

            except TimeoutError:

                continue

            except ConnectionError as e:

                print(
                    f"[!] Connexion fermée : {e}"
                )

                return

            except Exception as e:

                print(
                    f"[!] Réception : "
                    f"{type(e).__name__}: {e}"
                )

                continue

            if len(payload) < 2:

                continue

            hop = payload[0]
            msg_type = payload[1]
            body = payload[2:]

            print(
                f"[←] frame={len(payload):,}o "
                f"type=0x{msg_type:02x} "
                f"hop={hop}"
            )

            if msg_type == K_ACK:

                ids = body.decode(
                    errors="replace"
                ).split(",")

                for message_id in ids:

                    message_id = (
                        message_id.strip()
                    )

                    if not message_id:
                        continue

                    self.stats["acks_rx"] += 1

                    print(
                        f"[✓] ACK reçu : "
                        f"{message_id}"
                    )

                    if (
                        message_id ==
                        self.file_id
                    ):

                        print(
                            "[✓] ACK DU FICHIER 50 MiB"
                        )

            elif msg_type == K_TEXT:

                try:

                    obj = json.loads(
                        body.decode()
                    )

                    print(
                        "[←] JSON :",
                        obj
                    )

                except Exception:

                    print(
                        "[←] Texte :",
                        body[:500]
                    )

            else:

                print(
                    f"[!] Type non traité : "
                    f"0x{msg_type:02x}"
                )

    # ========================================================================
    # TEST COMPLET
    # ========================================================================

    def run(self):

        sha256 = None
        transfer_started = False

        try:

            self.send_hello()

            time.sleep(
                0.5
            )

            transfer_started = True

            sha256 = self.calculate_sha256()

            # Pour éviter de recalculer le SHA-256 inutilement,
            # send_50mb() accepte ici le SHA déjà calculé.
            prefix = self.build_file_payload(
                sha256
            )

            payload_size = (
                len(prefix) +
                FILE_SIZE
            )

            print()
            print("=" * 64)
            print(
                "ENVOI DU FICHIER"
            )
            print("=" * 64)

            print(
                f"fileId       : {self.file_id}"
            )

            print(
                f"Taille       : "
                f"{FILE_SIZE:,} octets"
            )

            print(
                f"SHA-256      : {sha256}"
            )

            print(
                f"Payload      : "
                f"{payload_size:,} octets"
            )

            print()

            start = time.monotonic()

            # Longueur TCP.
            self.sock.sendall(
                struct.pack(
                    ">I",
                    payload_size
                )
            )

            # Header applicatif.
            self.sock.sendall(
                prefix
            )

            sha_verify = hashlib.sha256()

            sent = 0
            last_print = 0

            for block in self.generate_content(
                FILE_SIZE
            ):

                self.sock.sendall(
                    block
                )

                sha_verify.update(
                    block
                )

                sent += len(block)

                now = time.monotonic()

                if (
                    now - last_print >= 0.5
                    or sent == FILE_SIZE
                ):

                    elapsed = max(
                        now - start,
                        0.001
                    )

                    percent = (
                        sent /
                        FILE_SIZE *
                        100
                    )

                    mib = (
                        sent /
                        1024 /
                        1024
                    )

                    speed = (
                        sent /
                        elapsed /
                        1024 /
                        1024
                    )

                    print(
                        f"\r[→] "
                        f"{percent:6.2f}% "
                        f"{mib:6.2f}/50.00 MiB "
                        f"{speed:.2f} MiB/s",
                        end="",
                        flush=True
                    )

                    last_print = now

            print()

            elapsed = (
                time.monotonic() -
                start
            )

            speed = (
                FILE_SIZE /
                elapsed /
                1024 /
                1024
            )

            actual_sha = (
                sha_verify.hexdigest()
            )

            print()
            print(
                "[✓] 50 MiB envoyés"
            )

            print(
                f"    durée : "
                f"{elapsed:.2f}s"
            )

            print(
                f"    débit : "
                f"{speed:.2f} MiB/s"
            )

            print(
                f"    SHA-256 : "
                f"{actual_sha}"
            )

            if actual_sha != sha256:

                print(
                    "[✗] SHA-256 différent"
                )

            else:

                print(
                    "[✓] SHA-256 vérifié"
                )

            self.listen(
                30
            )

        except KeyboardInterrupt:

            print(
                "\n[!] Interrompu"
            )

        except BrokenPipeError:

            print(
                "\n[✗] Droplet a fermé "
                "la connexion pendant l'envoi."
            )

        except socket.timeout:

            print(
                "\n[✗] Timeout TCP."
            )

        except Exception as e:

            print(
                "\n[✗] ERREUR : "
                f"{type(e).__name__}: {e}"
            )

        finally:

            print()
            print("=" * 64)
            print(
                "RÉSUMÉ"
            )
            print("=" * 64)

            print(
                f"Frames TX : "
                f"{self.stats['frames_tx']}"
            )

            print(
                f"Frames RX : "
                f"{self.stats['frames_rx']}"
            )

            print(
                f"ACK RX    : "
                f"{self.stats['acks_rx']}"
            )

            print(
                f"Octets TX : "
                f"{self.stats['bytes_tx']:,}"
            )

            print(
                f"File ID   : "
                f"{self.file_id}"
            )

            print("=" * 64)

            if self.sock:

                try:
                    self.sock.close()

                except Exception:

                    pass


# ============================================================================
# MAIN
# ============================================================================

def main():

    target_ip = None
    target_port = None

    if len(sys.argv) >= 2:

        target_ip = sys.argv[1]

    if len(sys.argv) >= 3:

        target_port = int(
            sys.argv[2]
        )

    peer = FakePeer(
        target_ip,
        target_port
    )

    peer.run()


if __name__ == "__main__":

    main()
