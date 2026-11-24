#!/usr/bin/env python3
import os
import re
import sys
import time
import json
import queue
import socket
import threading
import subprocess
import urllib.request
import urllib.parse
from pathlib import Path

# =====================================
# OGHOST MULTI-VPS PINGGY MANAGER
# =====================================

NODE_ID = os.environ["NODE_ID"]
CF_TOKEN = os.environ["CF_API_TOKEN"]
ZONE_ID = os.environ["CF_ZONE_ID"]

DOMAIN = "in-2g.oghost.qzz.io"
LOCAL_PORT = 8787

PINGGY_HOST = "ap.free.pinggy.io"
PINGGY_USER = "tcp"

ROTATION = 50 * 60
HEARTBEAT = 15
DRAIN_SECONDS = 30
START_TIMEOUT = 90

CF_API = "https://api.cloudflare.com/client/v4"
BASE = Path.home() / ".oghost-tunnel" / NODE_ID
BASE.mkdir(parents=True, exist_ok=True)

if not re.fullmatch(r"[a-zA-Z0-9-]{1,30}", NODE_ID):
    raise ValueError("Invalid NODE_ID")

CNAME = f"{NODE_ID}.{DOMAIN}"
SRV = f"_oghost._tcp.{CNAME}"


def log(message):
    print(time.strftime("[%Y-%m-%d %H:%M:%S]"),
          f"[{NODE_ID}] {message}", flush=True)


# =====================================
# CLOUDFLARE
# =====================================

def cf(method, path, data=None):
    body = json.dumps(data).encode() if data is not None else None

    req = urllib.request.Request(
        CF_API + path,
        data=body,
        method=method,
        headers={
            "Authorization": f"Bearer {CF_TOKEN}",
            "Content-Type": "application/json"
        }
    )

    with urllib.request.urlopen(req, timeout=20) as response:
        result = json.loads(response.read())

    if not result.get("success"):
        raise RuntimeError(str(result.get("errors")))

    return result.get("result", [])


def record(record_type, name):
    query = urllib.parse.urlencode({
        "type": record_type,
        "name": name
    })

    records = cf(
        "GET",
        f"/zones/{ZONE_ID}/dns_records?{query}"
    )

    return records[0] if records else None


def upsert(record_type, name, payload):
    path = f"/zones/{ZONE_ID}/dns_records"
    old = record(record_type, name)

    if old:
        cf("PATCH", path + "/" + old["id"], payload)
    else:
        cf("POST", path, payload)


def snapshot_dns():
    return {
        "cname": record("CNAME", CNAME),
        "srv": record("SRV", SRV)
    }


def restore_one(record_type, name, old):
    path = f"/zones/{ZONE_ID}/dns_records"
    current = record(record_type, name)

    if old:
        payload = {
            "type": record_type,
            "name": name,
            "ttl": old["ttl"]
        }

        if record_type == "CNAME":
            payload.update({
                "content": old["content"],
                "proxied": old.get("proxied", False)
            })
        else:
            payload["data"] = old["data"]

        cf("PATCH", path + "/" + old["id"], payload)

    elif current:
        cf("DELETE", path + "/" + current["id"])


def update_dns(host, port):
    upsert("CNAME", CNAME, {
        "type": "CNAME",
        "name": CNAME,
        "content": host,
        "ttl": 1,
        "proxied": False
    })

    upsert("SRV", SRV, {
        "type": "SRV",
        "name": SRV,
        "ttl": 1,
        "data": {
            "priority": 0,
            "weight": 0,
            "port": int(port),
            "target": host
        }
    })

    c = record("CNAME", CNAME)
    s = record("SRV", SRV)

    if not c or c["content"] != host:
        raise RuntimeError("CNAME verification failed")

    if not s:
        raise RuntimeError("SRV verification failed")

    data = s["data"]

    if data["target"] != host or int(data["port"]) != int(port):
        raise RuntimeError("SRV verification failed")

    log(f"DNS VERIFIED: {host}:{port}")


# =====================================
# LOCAL NODE HEALTH
# =====================================

def local_health():
    try:
        with socket.create_connection(
            ("127.0.0.1", LOCAL_PORT), timeout=3
        ):
            return True
    except OSError:
        return False


# =====================================
# PINGGY TUNNEL
# =====================================

def start_tunnel():
    log("Starting new Pinggy tunnel")

    command = [
        "ssh",
        "-p", "443",
        "-o", "StrictHostKeyChecking=no",
        "-o", "ServerAliveInterval=30",
        "-o", "ServerAliveCountMax=3",
        "-o", "ExitOnForwardFailure=yes",
        "-R0:localhost:8787",
        f"{PINGGY_USER}@{PINGGY_HOST}"
    ]

    proc = subprocess.Popen(
        command,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1
    )

    lines = queue.Queue()

    def reader():
        try:
            for line in proc.stdout:
                lines.put(line)
        finally:
            lines.put(None)

    threading.Thread(target=reader, daemon=True).start()

    deadline = time.time() + START_TIMEOUT
    endpoint = None

    pattern = re.compile(
        r"tcp://([a-zA-Z0-9.-]+):(\d+)"
    )

    while time.time() < deadline:
        if proc.poll() is not None:
            break

        try:
            line = lines.get(timeout=1)
        except queue.Empty:
            continue

        if line is None:
            break

        line = line.strip()
        if line:
            log("SSH: " + line[:250])

        match = pattern.search(line)

        if match:
            endpoint = (match.group(1), int(match.group(2)))
            break

    if not endpoint:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

        raise RuntimeError(
            "Pinggy TCP address not detected. "
            "Check Pinggy SSH output."
        )

    host, port = endpoint

    if proc.poll() is not None:
        raise RuntimeError("Tunnel closed during startup")

    log(f"NEW TUNNEL: {host}:{port}")

    return {
        "process": proc,
        "host": host,
        "port": port
    }


def stop_tunnel(tunnel):
    if not tunnel:
        return

    proc = tunnel["process"]

    if proc.poll() is None:
        proc.terminate()

        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    log("Tunnel stopped")


# =====================================
# MANAGER
# =====================================

def main():
    active = None
    next_rotation = 0

    log("OGHOST TUNNEL MANAGER STARTED")
    log(f"CNAME: {CNAME}")
    log(f"SRV: {SRV}")

    while True:
        try:
            if not local_health():
                log("WARNING: Local port 8787 unavailable")
                time.sleep(HEARTBEAT)
                continue

            if (
                active
                and active["process"].poll() is None
                and time.time() < next_rotation
            ):
                time.sleep(HEARTBEAT)
                log("HEARTBEAT: Node port healthy")
                continue

            old = active

            log("Preparing candidate tunnel...")

            candidate = start_tunnel()
            previous_dns = snapshot_dns()

            try:
                update_dns(
                    candidate["host"],
                    candidate["port"]
                )

            except Exception:
                log("DNS update failed; rolling back")

                try:
                    restore_one("CNAME", CNAME, previous_dns["cname"])
                    restore_one("SRV", SRV, previous_dns["srv"])
                except Exception as e:
                    log(f"ROLLBACK ERROR: {e}")

                stop_tunnel(candidate)
                raise

            # New tunnel activated
            active = candidate
            next_rotation = time.time() + ROTATION

            log("NEW TUNNEL ACTIVE")

            # Give DNS caches time to refresh
            if old:
                log(f"Old tunnel draining for {DRAIN_SECONDS}s")

                end = time.time() + DRAIN_SECONDS

                while time.time() < end:
                    if active["process"].poll() is not None:
                        log("New tunnel failed during drain")
                        break

                    time.sleep(HEARTBEAT)

                if active["process"].poll() is None:
                    stop_tunnel(old)
                else:
                    # Restore previous DNS and retain old if alive
                    try:
                        restore_dns(old["host"], old["port"])
                    except Exception as e:
                        log(f"DNS rollback error: {e}")

                    stop_tunnel(active)
                    active = old
                    next_rotation = time.time() + HEARTBEAT

            log("Tunnel manager cycle completed")

        except KeyboardInterrupt:
            log("Stopping manager")
            stop_tunnel(active)
            break

        except Exception as e:
            log(f"ERROR: {e}")
            log("Retrying in 15 seconds")
            time.sleep(HEARTBEAT)


if __name__ == "__main__":
    main()
