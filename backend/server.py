import asyncio
import hmac
import ipaddress
import logging
import os
import platform
import secrets
import socket
import threading
import time
from contextlib import asynccontextmanager
from pathlib import Path

import psutil
import uvicorn
from fastapi import FastAPI, Header, HTTPException
from fastapi.staticfiles import StaticFiles

UI = Path(__file__).resolve().parents[1] / "frontend"
PRIVATE = tuple(map(ipaddress.ip_network, ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")))
TOKEN_FILE = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "NEXUS" / "pairing.token"


def get_token():
    TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
    try:
        with TOKEN_FILE.open("x", encoding="ascii") as stream:
            stream.write(secrets.token_urlsafe(32))
    except FileExistsError:
        pass
    token = TOKEN_FILE.read_text(encoding="ascii").strip()
    if len(token) < 40 or not token.isascii() or not token.isprintable():
        raise ValueError(f"Invalid token file. Move {TOKEN_FILE} aside and restart.")
    return token


def sample_loop(state, stop):
    root = os.environ.get("SystemDrive", "C:") + os.sep
    previous = None
    psutil.cpu_percent()  # Prime this thread's CPU counter before measuring.
    while not stop.wait(2):
        try:
            now = time.monotonic()
            net = psutil.net_io_counters()
            sent = net.bytes_sent if net else None
            received = net.bytes_recv if net else None
            up = down = None
            if previous and net:
                then, old_sent, old_received = previous
                if sent >= old_sent and received >= old_received:
                    up = (sent - old_sent) / (now - then)
                    down = (received - old_received) / (now - then)
            previous = (now, sent, received) if net else None
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage(root)
            try:
                frequency = psutil.cpu_freq()
            except (OSError, NotImplementedError, psutil.Error):
                frequency = None
            state.latest = (now, dict(
                sampled_at=time.time(), hostname=socket.gethostname(), os=platform.platform(),
                uptime_seconds=max(0, int(time.time() - psutil.boot_time())),
                cpu_percent=psutil.cpu_percent(),
                cpu_mhz=frequency.current if frequency and frequency.current > 0 else None,
                ram_percent=memory.percent, ram_total=memory.total, ram_available=memory.available,
                disk_percent=disk.percent, disk_total=disk.total, disk_free=disk.free, drive=root,
                sent_bytes=sent, received_bytes=received, upload_bps=up, download_bps=down,
            ))
        except Exception:
            state.latest = None
            logging.exception("Telemetry unavailable. Retrying in two seconds.")


@asynccontextmanager
async def lifespan(app):
    app.state.token = get_token()
    app.state.latest = None
    stop = threading.Event()
    worker = threading.Thread(target=sample_loop, args=(app.state, stop), daemon=True)
    worker.start()
    try:
        yield
    finally:
        stop.set()
        await asyncio.to_thread(worker.join, 3)


app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)


@app.middleware("http")
async def security_headers(request, call_next):
    response = await call_next(request)
    response.headers.update({
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
        "Referrer-Policy": "no-referrer",
        "Content-Security-Policy": "default-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
    })
    return response


@app.get("/api/v1/status")
def status():
    return {"online": True}


@app.get("/api/v1/stats")
def stats(authorization: str = Header(default="")):
    expected = ("Bearer " + app.state.token).encode()
    if not hmac.compare_digest(authorization.encode(), expected):
        raise HTTPException(401, "Check the pairing token.", headers={"WWW-Authenticate": "Bearer"})
    latest = app.state.latest
    if latest is None or time.monotonic() - latest[0] > 8:
        raise HTTPException(503, "Waiting for a fresh system sample.")
    return latest[1]


app.mount("/", StaticFiles(directory=UI, html=True), name="dashboard")


def launch():
    hosts = ["127.0.0.1"]
    for addresses in psutil.net_if_addrs().values():
        for addr in addresses:
            if addr.family == socket.AF_INET and any(ipaddress.ip_address(addr.address) in n for n in PRIVATE):
                if addr.address not in hosts:
                    hosts.append(addr.address)
    for i, host in enumerate(hosts, start=1):
        print(f"{i}. {host}" + (" (this PC only)" if i == 1 else " (LAN interface)"))
    choice = int(input("Choose the address to listen on [1]: ").strip() or "1")
    if not 1 <= choice <= len(hosts):
        raise ValueError("Choose a listed address.")
    port = int(input("Port [8765]: ").strip() or "8765")
    if not 1 <= port <= 65535:
        raise ValueError("Choose a port between 1 and 65535.")
    get_token()
    print(f"Open http://{hosts[choice-1]}:{port}/")
    print(f"Open this file privately in Notepad for your token: {TOKEN_FILE}", flush=True)
    uvicorn.run(app, host=hosts[choice-1], port=port, proxy_headers=False, access_log=False)


if __name__ == "__main__":
    try:
        launch()
    except (ValueError, OSError, EOFError) as error:
        raise SystemExit(str(error))
