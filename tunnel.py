#!/usr/bin/env python3

import os
import re
import time
import threading
import subprocess
import requests
import pexpect

# ============ CONFIGURATION ============

NODE_ID = os.getenv("NODE_ID", "n001")
CF_API_TOKEN = os.getenv("CF_API_TOKEN", "")
CF_ZONE_ID = os.getenv("CF_ZONE_ID", "")

DOMAIN = f"{NODE_ID}.in-2g.oghost.qzz.io"
SRV_NAME = f"_oghost._tcp.{DOMAIN}"

LOCAL_PORT = 8787
ROTATE_SECONDS = 3000
HEARTBEAT_SECONDS = 15

PINGGY_HOST = "ap.free.pinggy.io"

API = f"https://api.cloudflare.com/client/v4/zones/{CF_ZONE_ID}/dns_records"

HEADERS = {
    "Authorization": f"Bearer {CF_API_TOKEN}",
    "Content-Type": "application/json"
}

# =======================================

if not CF_API_TOKEN or not CF_ZONE_ID:
    raise SystemExit("ERROR: CF_API_TOKEN aur CF_ZONE_ID set karo.")

def cf_request(method, url, **kwargs):
    response = requests.request(
        method, url, headers=HEADERS,
        timeout=20, **kwargs
    )
    response.raise_for_status()
    data = response.json()

    if not data.get("success"):
        raise RuntimeError(str(data.get("errors")))

    return data

def find_record(name, record_type):
    result = cf_request(
        "GET", API,
        params={"name": name, "type": record_type}
    )
    return result["result"][0] if result["result"] else None

def update_record(record_type, name, content, **extra):
    record = find_record(name, record_type)

    payload = {
        "type": record_type,
        "name": name,
        "content": content,
        "ttl": 60,
        **extra
    }

    if record:
        return cf_request(
            "PUT", f"{API}/{record['id']}",
            json=payload
        )["result"]

    return cf_request("POST", API, json=payload)["result"]

def update_dns(host, port):
    update_record("CNAME", DOMAIN, host)

    update_record(
        "SRV",
        SRV_NAME,
        f"1 1 {port} {host}",
        data={
            "service": "_oghost",
            "proto": "_tcp",
            "name": DOMAIN,
            "priority": 1,
            "weight": 1,
            "port": int(port),
            "target": host
        }
    )

    print(f"[DNS] Updated: {DOMAIN} -> {host}:{port}")

def start_tunnel():
    command = (
        f"ssh -tt -p 443 "
        f"-o StrictHostKeyChecking=no "
        f"-o ServerAliveInterval=30 "
        f"-o ServerAliveCountMax=3 "
        f"-o ExitOnForwardFailure=yes "
        f"-R0:localhost:{LOCAL_PORT} "
        f"tcp@{PINGGY_HOST}"
    )

    print("[PINGGY] Connecting...")

    child = pexpect.spawn(
        command,
        encoding="utf-8",
        timeout=30
    )

    host = None
    port = None
    last_enter = 0

    while True:
        try:
            index = child.expect(
                [
                    r"(?i)password:",
                    r"(?i)press\s+enter",
                    r"(?i)hit\s+enter",
                    r"tcp://([a-zA-Z0-9.-]+):([0-9]+)",
                    pexpect.TIMEOUT,
                    pexpect.EOF
                ],
                timeout=10
            )

            if index == 0:
                # Empty password: send Enter without typing anything
                child.sendline("")
                last_enter = time.time()

            elif index in (1, 2):
                child.sendline("")
                last_enter = time.time()

            elif index == 3:
                host = child.match.group(1)
                port = int(child.match.group(2))
                print(f"[PINGGY] Public endpoint: {host}:{port}")
                return child, host, port

            elif index == 4:
                if not child.isalive():
                    break

            elif index == 5:
                break

        except Exception as error:
            print("[PINGGY ERROR]", error)
            break

    print("[PINGGY] Tunnel did not start.")
    try:
        print(child.before)
    except Exception:
        pass

    child.close(force=True)
    return None, None, None

def heartbeat():
    while True:
        print(f"[HEARTBEAT] {NODE_ID} alive")
        time.sleep(HEARTBEAT_SECONDS)

def main():
    threading.Thread(
        target=heartbeat,
        daemon=True
    ).start()

    while True:
        child = None

        try:
            child, host, port = start_tunnel()

            if not child:
                time.sleep(5)
                continue

            update_dns(host, port)

            print("[OGHOST] Tunnel active.")

            started = time.time()

            while child.isalive():
                if time.time() - started >= ROTATE_SECONDS:
                    print("[ROTATION] Starting new tunnel...")
                    break

                time.sleep(2)

        except KeyboardInterrupt:
            print("\n[OGHOST] Stopping...")
            break

        except Exception as error:
            print("[ERROR]", error)

        finally:
            if child:
                child.close(force=True)

        time.sleep(3)

if __name__ == "__main__":
    main()
