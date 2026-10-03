#!/usr/bin/env python3
"""AirDrop for Golden Gate: share files with devices nearby.

Speaks the LocalSend protocol (v2, https://github.com/localsend/protocol), so
it works with the LocalSend app on iPhone, iPad, Android, Windows, macOS and
Linux as well as with other Golden Gate computers:

  discovery  UDP multicast 224.0.0.167:53317 announcements, answered with an
             HTTP register call; plus a sweep of the local /24 when asked,
             for networks that drop multicast
  receiving  HTTPS on port 53317: prepare-upload asks you to Accept or
             Decline, then each file streams into ~/Downloads
  sending    prepare-upload to the other device, then one upload per file

The service runs for the whole session (`airdropd.py serve`). The AirDrop app
talks to it over a Unix socket in JSON lines, through `airdropd.py client`,
which relays stdin/stdout and starts the service if it isn't running:

  → {"cmd": "hello"}                       ← {"event": "state", ...}
  → {"cmd": "scan"}                        ← {"event": "peers", "peers": [...]}
  → {"cmd": "send", "to": FP, "paths": []} ← {"event": "transfer", ...}
  → {"cmd": "cancel", "to": FP}
  → {"cmd": "answer", "id": ID, "accept": true}
                                           ← {"event": "request", ...}
  → {"cmd": "set", "discoverable": "everyone" | "off", "alias": "..."}

With no app open, an incoming request becomes a notification with Accept and
Decline. Standard library only; the certificate comes from openssl(1), and
without it the service falls back to plain HTTP, which LocalSend supports.
"""
from __future__ import annotations

import asyncio
import hashlib
import ipaddress
import json
import mimetypes
import os
import re
import secrets
import shutil
import socket
import ssl
import struct
import subprocess
import sys
import time
import uuid
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

MULTICAST = "224.0.0.167"
PORT = int(os.environ.get("GG_AIRDROP_PORT", "53317"))
API = "/api/localsend/v2"
VERSION = "2.1"
REQUEST_TIMEOUT = 90          # seconds to answer an incoming request
# Our certificate, shown to other devices when we connect to them too: over
# HTTPS a LocalSend device knows who is calling by the certificate's hash.
CLIENT_CERT: tuple[str, str] | None = None
PEER_TTL = 15 * 60            # a device stays listed this long after it was last heard


def runtime_dir() -> Path:
    return Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}")


def socket_path() -> Path:
    return Path(os.environ.get("GG_AIRDROP_SOCKET") or runtime_dir() / "gg-airdrop.sock")


def config_dir() -> Path:
    base = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    return base / "golden-gate"


def data_dir() -> Path:
    base = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local/share")
    return base / "golden-gate" / "airdrop"


def downloads_dir() -> Path:
    if os.environ.get("GG_AIRDROP_DOWNLOADS"):
        return Path(os.environ["GG_AIRDROP_DOWNLOADS"])
    try:
        out = subprocess.run(["xdg-user-dir", "DOWNLOAD"], capture_output=True, text=True, timeout=2).stdout.strip()
        if out and out != str(Path.home()):
            return Path(out)
    except (OSError, subprocess.SubprocessError):
        pass
    return Path.home() / "Downloads"


def computer_name() -> str:
    for cmd in (["hostnamectl", "--pretty"],):
        try:
            name = subprocess.run(cmd, capture_output=True, text=True, timeout=2).stdout.strip()
            if name:
                return name
        except (OSError, subprocess.SubprocessError):
            pass
    host = socket.gethostname().split(".")[0]
    return host if host and host not in ("localhost", "archiso") else "Golden Gate"


def safe_relative(name: str) -> Path | None:
    """A sender's file name as a path under Downloads (LocalSend sends
    "folder/file" for folders), refusing anything that could leave it."""
    parts = [p for p in re.split(r"[\\/]+", name or "") if p not in ("", ".")]
    if not parts or any(p == ".." for p in parts):
        return None
    parts = [re.sub(r"[\x00-\x1f]", "", p)[:200] or "file" for p in parts]
    return Path(*parts)


def unique(path: Path) -> Path:
    if not path.exists():
        return path
    stem, suffix = path.stem, path.suffix
    for n in range(2, 10000):
        candidate = path.with_name(f"{stem} {n}{suffix}")
        if not candidate.exists():
            return candidate
    return path.with_name(f"{stem} {uuid.uuid4().hex[:6]}{suffix}")


# ---------------------------------------------------------------- HTTP plumbing
class HttpError(Exception):
    def __init__(self, status: int, message: str = ""):
        super().__init__(message)
        self.status = status
        self.message = message


REASONS = {200: "OK", 204: "No Content", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
           404: "Not Found", 409: "Conflict", 429: "Too Many Requests", 500: "Internal Server Error"}


async def read_request(reader: asyncio.StreamReader):
    line = await reader.readline()
    if not line:
        return None
    try:
        method, target, _ = line.decode("latin-1").split(" ", 2)
    except ValueError:
        raise HttpError(400, "bad request line")
    headers = {}
    while True:
        h = await reader.readline()
        if h in (b"\r\n", b"\n", b""):
            break
        k, _, v = h.decode("latin-1").partition(":")
        headers[k.strip().lower()] = v.strip()
    return method.upper(), target, headers


async def body_chunks(reader: asyncio.StreamReader, headers: dict):
    """The request body, as it arrives: Content-Length or chunked."""
    if headers.get("transfer-encoding", "").lower() == "chunked":
        while True:
            size = int((await reader.readline()).split(b";")[0].strip() or b"0", 16)
            if size == 0:
                while (await reader.readline()) not in (b"\r\n", b"\n", b""):
                    pass
                return
            left = size
            while left:
                chunk = await reader.read(min(left, 1 << 20))
                if not chunk:
                    raise HttpError(400, "body ended early")
                left -= len(chunk)
                yield chunk
            await reader.readline()
    else:
        left = int(headers.get("content-length", "0") or 0)
        while left > 0:
            chunk = await reader.read(min(left, 1 << 20))
            if not chunk:
                raise HttpError(400, "body ended early")
            left -= len(chunk)
            yield chunk


async def read_json(reader, headers, limit=4 << 20):
    data = b""
    async for chunk in body_chunks(reader, headers):
        data += chunk
        if len(data) > limit:
            raise HttpError(400, "body too large")
    try:
        return json.loads(data or b"{}")
    except ValueError:
        raise HttpError(400, "invalid JSON")


def respond(writer, status: int, payload=None):
    body = b"" if payload is None else json.dumps(payload).encode()
    head = f"HTTP/1.1 {status} {REASONS.get(status, 'OK')}\r\nContent-Length: {len(body)}\r\nConnection: close\r\n"
    if payload is not None:
        head += "Content-Type: application/json\r\n"
    writer.write(head.encode() + b"\r\n" + body)


async def http_call(peer: dict, method: str, path: str, payload=None, *, body_path: Path | None = None,
                    progress=None, timeout: float = 15.0):
    """One request to another device. Returns (status, json-or-None)."""
    ctx = None
    if peer.get("protocol", "https") == "https":
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE       # LocalSend devices use self-signed certificates
        if CLIENT_CERT:
            ctx.load_cert_chain(*CLIENT_CERT)
    reader, writer = await asyncio.wait_for(
        asyncio.open_connection(peer["ip"], int(peer.get("port", PORT)), ssl=ctx), timeout=min(timeout, 6))
    try:
        if body_path is not None:
            length = body_path.stat().st_size
            ctype = "application/octet-stream"
        else:
            body = b"" if payload is None else json.dumps(payload).encode()
            length = len(body)
            ctype = "application/json"
        host = peer["ip"] if ":" not in peer["ip"] else f"[{peer['ip']}]"
        writer.write((f"{method} {path} HTTP/1.1\r\nHost: {host}:{peer.get('port', PORT)}\r\n"
                      f"Content-Type: {ctype}\r\nContent-Length: {length}\r\nConnection: close\r\n\r\n").encode())
        if body_path is not None:
            sent = 0
            with open(body_path, "rb") as f:
                while chunk := f.read(1 << 20):
                    writer.write(chunk)
                    await writer.drain()
                    sent += len(chunk)
                    if progress:
                        progress(sent)
        else:
            writer.write(body)
            await writer.drain()
        line = await asyncio.wait_for(reader.readline(), timeout=timeout)
        try:
            status = int(line.split()[1])
        except (IndexError, ValueError):
            raise HttpError(500, "bad response")
        headers = {}
        while True:
            h = await asyncio.wait_for(reader.readline(), timeout=timeout)
            if h in (b"\r\n", b"\n", b""):
                break
            k, _, v = h.decode("latin-1").partition(":")
            headers[k.strip().lower()] = v.strip()
        data = b""
        async for chunk in body_chunks(reader, headers):
            data += chunk
        if not headers.get("content-length") and not headers.get("transfer-encoding"):
            data += await reader.read()
        try:
            parsed = json.loads(data) if data.strip() else None
        except ValueError:
            parsed = None
        return status, parsed
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except (OSError, ssl.SSLError):
            pass


# ---------------------------------------------------------------- the service
class AirDrop:
    def __init__(self):
        self.settings_file = config_dir() / "airdrop.json"
        self.settings = self.load_settings()
        self.peers: dict[str, dict] = {}
        self.clients: set[asyncio.StreamWriter] = set()
        self.requests: dict[str, dict] = {}       # incoming, waiting for an answer
        self.session: dict | None = None          # the incoming transfer in progress
        self.outgoing: dict[str, dict] = {}       # fingerprint → transfer to that device
        self.protocol = "http"
        self.ssl_ctx: ssl.SSLContext | None = None
        self.fingerprint = self.settings.setdefault("fingerprint", secrets.token_hex(32))
        self.setup_tls()
        self.udp: socket.socket | None = None

    # ----------------------------------------------------------- settings
    def load_settings(self) -> dict:
        try:
            data = json.loads(self.settings_file.read_text())
            return data if isinstance(data, dict) else {}
        except (OSError, ValueError):
            return {}

    def save_settings(self):
        self.settings_file.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.settings_file.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.settings, indent=2))
        tmp.replace(self.settings_file)

    @property
    def alias(self) -> str:
        return self.settings.get("alias") or computer_name()

    @property
    def discoverable(self) -> str:
        return self.settings.get("discoverable", "everyone")

    def setup_tls(self):
        folder = data_dir()
        cert, key = folder / "cert.pem", folder / "key.pem"
        if os.environ.get("GG_AIRDROP_HTTP") != "1" and shutil.which("openssl"):
            if not (cert.exists() and key.exists()):
                folder.mkdir(parents=True, exist_ok=True)
                os.chmod(folder, 0o700)
                subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256",
                                "-keyout", str(key), "-out", str(cert), "-days", "3650",
                                "-subj", "/CN=Golden Gate AirDrop"],
                               capture_output=True, timeout=60)
            if cert.exists() and key.exists():
                os.chmod(key, 0o600)
                try:
                    ctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
                    ctx.load_cert_chain(str(cert), str(key))
                    self.ssl_ctx = ctx
                    self.protocol = "https"
                    der = ssl.PEM_cert_to_DER_cert(cert.read_text())
                    self.fingerprint = hashlib.sha256(der).hexdigest()
                    global CLIENT_CERT
                    CLIENT_CERT = (str(cert), str(key))
                except (ssl.SSLError, OSError, ValueError):
                    self.ssl_ctx = None
                    self.protocol = "http"

    def info(self, *, announce=None) -> dict:
        data = {"alias": self.alias, "version": VERSION, "deviceModel": "Golden Gate",
                "deviceType": "desktop", "fingerprint": self.fingerprint, "port": PORT,
                "protocol": self.protocol, "download": False}
        if announce is not None:
            data["announce"] = announce
        return data

    # ----------------------------------------------------------- UI clients
    def emit(self, event: str, **data):
        line = (json.dumps({"event": event, **data}) + "\n").encode()
        for w in list(self.clients):
            try:
                w.write(line)
            except (OSError, RuntimeError):
                self.clients.discard(w)

    def peer_list(self):
        now = time.time()
        out = []
        for fp, p in self.peers.items():
            if now - p["seen"] > PEER_TTL:
                continue
            t = self.outgoing.get(fp)
            out.append({"fingerprint": fp, "alias": p.get("alias") or "Device",
                        "deviceModel": p.get("deviceModel") or "", "deviceType": p.get("deviceType") or "desktop",
                        "ip": p["ip"], "transfer": t and {k: t[k] for k in ("state", "sent", "total", "message")}})
        return sorted(out, key=lambda p: p["alias"].lower())

    def state(self):
        return {"alias": self.alias, "discoverable": self.discoverable, "protocol": self.protocol,
                "downloads": str(downloads_dir()), "peers": self.peer_list(),
                "requests": [self.public_request(r) for r in self.requests.values()]}

    def publish_peers(self):
        self.emit("peers", peers=self.peer_list())

    def add_peer(self, info: dict, ip: str):
        fp = str(info.get("fingerprint") or "")
        if not fp or fp == self.fingerprint:
            return
        known = fp in self.peers
        self.peers[fp] = {"alias": str(info.get("alias") or "Device")[:80],
                          "deviceModel": str(info.get("deviceModel") or "")[:60],
                          "deviceType": str(info.get("deviceType") or "desktop"),
                          "ip": ip, "port": int(info.get("port") or PORT),
                          "protocol": "http" if info.get("protocol") == "http" else "https",
                          "seen": time.time()}
        if not known:
            self.publish_peers()

    # ----------------------------------------------------------- discovery
    def start_udp(self):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        if hasattr(socket, "SO_REUSEPORT"):
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        s.bind(("", PORT))
        mreq = struct.pack("4s4s", socket.inet_aton(MULTICAST), socket.inet_aton("0.0.0.0"))
        try:
            s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
        except OSError:
            pass                                    # no multicast route yet; the sweep still works
        s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
        s.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 1)
        s.setblocking(False)
        self.udp = s
        asyncio.get_running_loop().add_reader(s.fileno(), self.on_udp)

    def on_udp(self):
        try:
            data, (ip, _) = self.udp.recvfrom(65536)
            msg = json.loads(data)
        except (OSError, ValueError):
            return
        if not isinstance(msg, dict) or msg.get("fingerprint") == self.fingerprint:
            return
        self.add_peer(msg, ip)
        if msg.get("announce") and self.discoverable != "off":
            asyncio.ensure_future(self.answer_announce(msg, ip))

    async def answer_announce(self, msg, ip):
        peer = {"ip": ip, "port": int(msg.get("port") or PORT),
                "protocol": "http" if msg.get("protocol") == "http" else "https"}
        try:
            await http_call(peer, "POST", f"{API}/register", self.info(), timeout=4)
        except (OSError, asyncio.TimeoutError, ssl.SSLError, HttpError):
            self.multicast(self.info(announce=False))

    def multicast(self, payload):
        if not self.udp or self.discoverable == "off":
            return
        try:
            self.udp.sendto(json.dumps(payload).encode(), (MULTICAST, PORT))
        except OSError:
            pass

    def local_networks(self):
        nets = set()
        try:
            out = subprocess.run(["ip", "-4", "-o", "addr", "show", "scope", "global"],
                                 capture_output=True, text=True, timeout=3).stdout
            for m in re.finditer(r"inet (\d+\.\d+\.\d+\.\d+)/(\d+)", out):
                iface = ipaddress.ip_interface(f"{m.group(1)}/{max(24, int(m.group(2)))}")
                if iface.network.num_addresses <= 256:
                    nets.add((iface.network, str(iface.ip)))
        except (OSError, subprocess.SubprocessError, ValueError):
            pass
        return nets

    async def scan(self):
        """Announce, and sweep the local network for devices that miss it."""
        self.multicast(self.info(announce=True))
        extra = [h for h in os.environ.get("GG_AIRDROP_PEERS", "").split(",") if h]
        targets = []
        for net, mine in self.local_networks():
            targets += [(str(h), PORT) for h in net.hosts() if str(h) != mine]
        for h in extra:
            host, _, port = h.rpartition(":")
            targets.append((host, int(port)))
        sem = asyncio.Semaphore(64)

        async def probe(ip, port):
            async with sem:
                for protocol in ("https", "http"):
                    try:
                        status, data = await http_call({"ip": ip, "port": port, "protocol": protocol},
                                                       "POST", f"{API}/register", self.info(), timeout=1.5)
                    except (OSError, asyncio.TimeoutError, ssl.SSLError, HttpError):
                        continue
                    if status == 200 and isinstance(data, dict):
                        data.setdefault("port", port)
                        data.setdefault("protocol", protocol)
                        self.add_peer(data, ip)
                    return
        await asyncio.gather(*(probe(ip, port) for ip, port in targets))
        self.publish_peers()

    # ----------------------------------------------------------- receiving
    def public_request(self, r):
        return {"id": r["id"], "from": r["from"], "deviceType": r["deviceType"], "files": r["summary"],
                "count": len(r["files"]), "size": r["size"], "text": r.get("text")}

    async def handle_http(self, reader, writer):
        ip = (writer.get_extra_info("peername") or ("?",))[0]
        try:
            req = await asyncio.wait_for(read_request(reader), timeout=20)
            if req is None:
                return
            method, target, headers = req
            url = urlsplit(target)
            query = {k: v[0] for k, v in parse_qs(url.query).items()}
            path = url.path.rstrip("/")
            if path in (f"{API}/register", "/api/localsend/v1/register") and method == "POST":
                info = await read_json(reader, headers)
                if self.discoverable == "off":
                    raise HttpError(403, "not discoverable")
                self.add_peer(info, ip)
                respond(writer, 200, {k: v for k, v in self.info().items() if k not in ("port", "protocol")})
            elif path == f"{API}/info" and method == "GET":
                respond(writer, 200, {k: v for k, v in self.info().items() if k not in ("port", "protocol")})
            elif path == f"{API}/prepare-upload" and method == "POST":
                await self.prepare_upload(await read_json(reader, headers), ip, writer)
            elif path == f"{API}/upload" and method == "POST":
                await self.upload(query, reader, headers, writer)
            elif path == f"{API}/cancel" and method == "POST":
                if self.session and query.get("sessionId") == self.session["id"]:
                    self.finish_session(cancelled=True)
                respond(writer, 200)
            else:
                respond(writer, 404, {"message": "Not found"})
        except HttpError as e:
            respond(writer, e.status, {"message": e.message or REASONS.get(e.status, "")})
        except (asyncio.TimeoutError, ConnectionError, ssl.SSLError, OSError):
            pass
        finally:
            try:
                await writer.drain()
                writer.close()
                await writer.wait_closed()
            except (OSError, ssl.SSLError, RuntimeError):
                pass

    async def prepare_upload(self, body, ip, writer):
        if self.discoverable == "off":
            raise HttpError(403, "AirDrop is off")
        info, files = body.get("info") or {}, body.get("files") or {}
        if not isinstance(files, dict) or not files:
            raise HttpError(400, "no files")
        if self.session or self.requests:
            raise HttpError(409, "busy")
        self.add_peer(info, ip)
        entries = []
        for fid, f in files.items():
            if not isinstance(f, dict):
                raise HttpError(400, "bad file")
            rel = safe_relative(str(f.get("fileName") or ""))
            if rel is None:
                raise HttpError(400, "bad file name")
            entries.append({"id": str(f.get("id") or fid), "name": str(rel), "size": int(f.get("size") or 0),
                            "type": str(f.get("fileType") or ""), "preview": f.get("preview")})
        sender = str(info.get("alias") or "Someone")[:80]
        # A message (text with its body in the preview) is shown, not saved.
        if len(entries) == 1 and entries[0]["type"].startswith("text/") and isinstance(entries[0]["preview"], str):
            text = entries[0]["preview"][:20000]
            self.emit("message", **{"from": sender, "text": text})
            if not self.clients:
                asyncio.ensure_future(notify(f"{sender} sent you a message", text[:300]))
            respond(writer, 204)
            return
        req = {"id": uuid.uuid4().hex, "from": sender, "deviceType": str(info.get("deviceType") or ""),
               "files": entries, "size": sum(e["size"] for e in entries),
               "summary": [e["name"] for e in entries[:6]], "answer": asyncio.get_running_loop().create_future()}
        self.requests[req["id"]] = req
        self.emit("request", **self.public_request(req))
        notifier = None
        if not self.clients:
            notifier = asyncio.ensure_future(self.ask_by_notification(req))
        try:
            accepted = await asyncio.wait_for(asyncio.shield(req["answer"]), timeout=REQUEST_TIMEOUT)
        except asyncio.TimeoutError:
            accepted = False
        finally:
            self.requests.pop(req["id"], None)
            if notifier:
                notifier.cancel()
            self.emit("request-done", id=req["id"])
        if not accepted:
            raise HttpError(403, "declined")
        tokens = {e["id"]: secrets.token_hex(16) for e in entries}
        self.session = {"id": uuid.uuid4().hex, "from": sender, "files": {e["id"]: e for e in entries},
                        "tokens": tokens, "done": set(), "saved": [], "received": 0,
                        "total": req["size"], "started": time.time()}
        self.emit("receiving", **{"from": sender, "received": 0, "total": req["size"], "count": len(entries)})
        respond(writer, 200, {"sessionId": self.session["id"], "files": tokens})

    async def ask_by_notification(self, req):
        count = len(req["files"])
        what = req["files"][0]["name"] if count == 1 else f"{count} items"
        answer = await notify(f"{req['from']} would like to share “{what}”", "AirDrop",
                              actions=[("decline", "Decline"), ("accept", "Accept")], wait=True)
        if not req["answer"].done():
            req["answer"].set_result(answer == "accept")

    async def upload(self, query, reader, headers, writer):
        s = self.session
        if not s or query.get("sessionId") != s["id"]:
            raise HttpError(403, "no such session")
        fid = query.get("fileId", "")
        if fid not in s["files"] or s["tokens"].get(fid) != query.get("token") or fid in s["done"]:
            raise HttpError(403, "bad token")
        entry = s["files"][fid]
        dest_root = downloads_dir()
        dest = unique(dest_root / entry["name"])
        dest.parent.mkdir(parents=True, exist_ok=True)
        part = dest.with_name(dest.name + ".download")
        last = 0.0
        try:
            with open(part, "wb") as f:
                async for chunk in body_chunks(reader, headers):
                    f.write(chunk)
                    s["received"] += len(chunk)
                    now = time.time()
                    if now - last > 0.15:
                        last = now
                        self.emit("receiving", **{"from": s["from"], "received": s["received"],
                                                  "total": s["total"], "count": len(s["files"])})
            part.replace(dest)
        except BaseException:
            part.unlink(missing_ok=True)
            raise
        s["done"].add(fid)
        s["saved"].append(str(dest))
        respond(writer, 200)
        if len(s["done"]) == len(s["files"]):
            self.finish_session()

    def finish_session(self, cancelled=False):
        s, self.session = self.session, None
        if not s:
            return
        self.emit("received", **{"from": s["from"], "paths": s["saved"], "cancelled": cancelled})
        if s["saved"] and not cancelled:
            n = len(s["saved"])
            what = Path(s["saved"][0]).name if n == 1 else f"{n} items"
            asyncio.ensure_future(notify(f"Received {what} from {s['from']}", "Saved to Downloads",
                                         actions=[("show", "Show in Files")], wait=True,
                                         on_action=lambda a: subprocess.Popen(
                                             ["sh", "-c", 'gg-files "$1" || xdg-open "$1"', "sh",
                                              str(Path(s["saved"][0]).parent)],
                                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)))

    # ----------------------------------------------------------- sending
    async def send(self, fp: str, paths: list[str]):
        peer = self.peers.get(fp)
        files = []
        for p in paths:
            path = Path(p)
            if path.is_dir():
                for sub in sorted(path.rglob("*")):
                    if sub.is_file():
                        files.append((sub, f"{path.name}/{sub.relative_to(path).as_posix()}"))
            elif path.is_file():
                files.append((path, path.name))
        if not peer or not files or fp in self.outgoing:
            return
        total = sum(f.stat().st_size for f, _ in files)
        t = self.outgoing[fp] = {"state": "waiting", "sent": 0, "total": total, "message": "", "session": None}

        def update(state=None, message=None):
            if state:
                t["state"] = state
            if message is not None:
                t["message"] = message
            self.emit("transfer", to=fp, state=t["state"], sent=t["sent"], total=t["total"], message=t["message"])

        update("waiting", "Waiting…")
        meta = {}
        for i, (path, name) in enumerate(files):
            fid = f"f{i}-{uuid.uuid4().hex[:8]}"
            meta[fid] = {"id": fid, "fileName": name, "size": path.stat().st_size,
                         "fileType": mimetypes.guess_type(name)[0] or "application/octet-stream",
                         "sha256": None, "preview": None}
        try:
            status, data = await http_call(peer, "POST", f"{API}/prepare-upload",
                                           {"info": self.info(), "files": meta}, timeout=REQUEST_TIMEOUT + 30)
            if status == 204:
                update("sent", "Sent")
                return
            if status == 403:
                update("declined", "Declined")
                return
            if status == 409:
                update("failed", "Busy")
                return
            if status != 200 or not isinstance(data, dict):
                update("failed", "Couldn't send")
                return
            session, tokens = data.get("sessionId"), data.get("files") or {}
            t["session"] = session
            update("sending", "Sending…")
            base = 0
            for (path, _), (fid, m) in zip(files, meta.items()):
                if t["state"] == "cancelled":
                    break
                if fid not in tokens:          # the receiver already has this one
                    base += m["size"]
                    continue
                last = [0.0]

                def progress(n, base=base):
                    t["sent"] = base + n
                    now = time.time()
                    if now - last[0] > 0.15:
                        last[0] = now
                        update()
                status, _ = await http_call(
                    peer, "POST", f"{API}/upload?sessionId={session}&fileId={fid}&token={tokens[fid]}",
                    body_path=path, progress=progress, timeout=120)
                if status != 200:
                    update("failed", "Couldn't send")
                    return
                base += m["size"]
            if t["state"] != "cancelled":
                t["sent"] = total
                update("sent", "Sent")
        except (OSError, asyncio.TimeoutError, ssl.SSLError, HttpError):
            update("failed", "Couldn't reach " + peer["alias"])
        finally:
            await asyncio.sleep(4)            # leave "Sent" under the device for a moment
            self.outgoing.pop(fp, None)
            self.publish_peers()

    async def cancel(self, fp):
        t, peer = self.outgoing.get(fp), self.peers.get(fp)
        if not t:
            return
        t["state"], t["message"] = "cancelled", "Cancelled"
        self.emit("transfer", to=fp, state="cancelled", sent=t["sent"], total=t["total"], message="Cancelled")
        if t.get("session") and peer:
            try:
                await http_call(peer, "POST", f"{API}/cancel?sessionId={t['session']}", timeout=4)
            except (OSError, asyncio.TimeoutError, ssl.SSLError, HttpError):
                pass

    # ----------------------------------------------------------- control socket
    async def handle_client(self, reader, writer):
        self.clients.add(writer)
        try:
            while line := await reader.readline():
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                await self.command(msg, writer)
        except (ConnectionError, OSError):
            pass
        finally:
            self.clients.discard(writer)
            writer.close()

    async def command(self, msg, writer):
        cmd = msg.get("cmd")
        if cmd == "hello":
            writer.write((json.dumps({"event": "state", **self.state()}) + "\n").encode())
        elif cmd == "scan":
            asyncio.ensure_future(self.scan())
        elif cmd == "send":
            asyncio.ensure_future(self.send(str(msg.get("to")), [str(p) for p in msg.get("paths") or []]))
        elif cmd == "cancel":
            await self.cancel(str(msg.get("to")))
        elif cmd == "answer":
            r = self.requests.get(str(msg.get("id")))
            if r and not r["answer"].done():
                r["answer"].set_result(bool(msg.get("accept")))
        elif cmd == "set":
            if msg.get("discoverable") in ("everyone", "off"):
                self.settings["discoverable"] = msg["discoverable"]
            if isinstance(msg.get("alias"), str):
                self.settings["alias"] = msg["alias"].strip()[:60]
            self.save_settings()
            self.emit("state", **self.state())
            if self.discoverable != "off":
                self.multicast(self.info(announce=True))

    async def serve(self):
        path = socket_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        if path.exists():
            path.unlink()
        control = await asyncio.start_unix_server(self.handle_client, path=str(path))
        os.chmod(path, 0o600)
        server = await asyncio.start_server(self.handle_http, host=None, port=PORT, ssl=self.ssl_ctx,
                                            reuse_address=True)
        self.start_udp()
        self.multicast(self.info(announce=True))
        print(f"AirDrop: {self.alias} on port {PORT} ({self.protocol})", flush=True)
        async with control, server:
            await asyncio.gather(control.serve_forever(), server.serve_forever())


async def notify(title, body, actions=(), wait=False, on_action=None):
    """A desktop notification; with actions, the chosen one's key (or "")."""
    if not shutil.which("notify-send"):
        return ""
    cmd = ["notify-send", "-a", "AirDrop", "-i", "org.goldengate.AirDrop", title, body]
    for key, label in actions:
        cmd += ["-A", f"{key}={label}"]
    if wait or actions:
        cmd.append("--wait")
    try:
        proc = await asyncio.create_subprocess_exec(*cmd, stdout=asyncio.subprocess.PIPE,
                                                    stderr=asyncio.subprocess.DEVNULL)
        out, _ = await proc.communicate()
    except asyncio.CancelledError:
        try:
            proc.kill()
        except (ProcessLookupError, UnboundLocalError):
            pass
        raise
    except OSError:
        return ""
    key = out.decode(errors="replace").strip()
    if key and on_action:
        on_action(key)
    return key


# ---------------------------------------------------------------- client relay
def client():
    """Relay JSON lines between stdin/stdout and the service, starting it first."""
    path = socket_path()

    def connect():
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(str(path))
        return s

    try:
        sock = connect()
    except OSError:
        subprocess.Popen([sys.executable, os.path.abspath(__file__), "serve"], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(50):
            time.sleep(0.1)
            try:
                sock = connect()
                break
            except OSError:
                continue
        else:
            print(json.dumps({"event": "error", "message": "AirDrop couldn't start."}), flush=True)
            return 1

    import threading

    def pump_in():
        for line in sys.stdin:
            try:
                sock.sendall(line.encode())
            except OSError:
                break
        os._exit(0)

    threading.Thread(target=pump_in, daemon=True).start()
    f = sock.makefile("rb")
    for line in f:
        sys.stdout.write(line.decode(errors="replace"))
        sys.stdout.flush()
    return 0


def set_discoverable(value: str) -> int:
    """Who can find this computer: through the service when it's running (so
    it announces itself again at once), or straight into its settings."""
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(str(socket_path()))
        s.sendall((json.dumps({"cmd": "set", "discoverable": value}) + "\n").encode())
        s.close()
        return 0
    except OSError:
        pass
    path = config_dir() / "airdrop.json"
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError):
        data = {}
    data["discoverable"] = value
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2))
    return 0


def main(argv):
    mode = argv[1] if len(argv) > 1 else "serve"
    if mode == "serve":
        try:
            asyncio.run(AirDrop().serve())
        except OSError as e:
            print(f"AirDrop couldn't start: {e}", file=sys.stderr)
            return 1
    elif mode == "client":
        return client()
    elif mode == "set" and len(argv) > 2 and argv[2] in ("everyone", "off"):
        return set_discoverable(argv[2])
    else:
        print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
