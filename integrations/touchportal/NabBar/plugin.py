#!/usr/bin/env python3
"""Touch Portal plugin: shows NabBar quotas as Touch Portal states.

Reads the status file NabBar exports (no network, no credentials)
and pushes one set of states per provider over Touch Portal's local socket.
"""
import json
import os
import socket
import threading
import time

PLUGIN_ID = "com.nabeegh.nabbar.touchportal"
TP_HOST, TP_PORT = "127.0.0.1", 12136
PROVIDERS = ["codex", "claude", "commandcode"]
STATUS_FILES = [
    os.path.expanduser("~/.nabbar/status.json"),
    os.path.expanduser("~/.claudebar/status.json"),
]
POLL_SECONDS = 5


def state_id(provider, field):
    return f"{PLUGIN_ID}.state.{provider}.{field}"


def read_status():
    for path in STATUS_FILES:
        try:
            with open(path) as f:
                return json.load(f)
        except (OSError, ValueError):
            continue
    return None


def provider_states(status):
    by_id = {p.get("id"): p for p in (status or {}).get("providers", [])}
    states = {}
    for pid in PROVIDERS:
        p = by_id.get(pid, {})
        left, used = p.get("percentRemaining"), p.get("percentUsed")
        states[state_id(pid, "left")] = f"{round(left)}%" if left is not None else "--"
        states[state_id(pid, "used")] = f"{round(used)}%" if used is not None else "--"
        states[state_id(pid, "reset")] = p.get("resetText") or ""
        states[state_id(pid, "status")] = p.get("status") or "unknown"
        label = p.get("name") or pid
        states[state_id(pid, "summary")] = (
            f"{label}\n{round(left)}% left" if left is not None else f"{label}\n--"
        )
    states[f"{PLUGIN_ID}.state.updatedAt"] = (status or {}).get("updatedAt", "")
    return states


class Plugin:
    def __init__(self):
        self.sock = socket.create_connection((TP_HOST, TP_PORT))
        self.running = True
        self.sent = {}

    def send(self, message):
        self.sock.sendall((json.dumps(message) + "\n").encode())

    def listen(self):
        buf = b""
        while self.running:
            chunk = self.sock.recv(4096)
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                if msg.get("type") == "closePlugin" and msg.get("pluginId") == PLUGIN_ID:
                    self.running = False
        self.running = False

    def run(self):
        self.send({"type": "pair", "id": PLUGIN_ID})
        threading.Thread(target=self.listen, daemon=True).start()
        while self.running:
            for sid, value in provider_states(read_status()).items():
                if self.sent.get(sid) != value:
                    self.send({"type": "stateUpdate", "id": sid, "value": value})
                    self.sent[sid] = value
            time.sleep(POLL_SECONDS)
        self.sock.close()


if __name__ == "__main__":
    Plugin().run()
