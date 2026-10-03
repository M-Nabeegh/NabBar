#!/usr/bin/env python3
"""Touch Portal plugin: shows NabBar quotas as Touch Portal states.

Reads the status file NabBar exports (no network, no credentials) and pushes
one set of states per provider over Touch Portal's local socket:

  <id>.left / .used / .reset    the first window (Claude and Codex: 5 hours)
  <id>.weekLeft / .weekReset    the weekly window
  <id>.level / .weekLevel       green, yellow, red or depleted (NabBar's thresholds)
  <id>.status / .summary        text; summary reads "Claude\n5h 44% · 7d 80%"
  <id>.icon                     a base64 PNG: one bar per window, filled to the % left

"Refresh NabBar" asks NabBar to refresh through its nabbar://refresh URL.
"""
import base64
import json
import os
import socket
import struct
import subprocess
import threading
import time
import zlib

PLUGIN_ID = "com.nabeegh.nabbar.touchportal"
REFRESH_ACTION = f"{PLUGIN_ID}.action.refresh"
TP_HOST, TP_PORT = "127.0.0.1", 12136
PROVIDERS = ["codex", "claude", "commandcode"]
STATUS_FILES = [os.path.expanduser("~/.nabbar/status.json")]
POLL_SECONDS = 5

# NabBar's status colours: more than 50% left, 20-50%, under 20%, nothing left.
LEVEL_COLOURS = {
    "green": (0x4F, 0xE3, 0xA6),
    "yellow": (0xF7, 0xB9, 0x55),
    "red": (0xF2, 0x68, 0x7E),
    "depleted": (0xD9, 0x3D, 0x55),
    "unknown": (0x6B, 0x70, 0x78),
}
ICON_SIZE = 128


def state_id(provider, field):
    return f"{PLUGIN_ID}.state.{provider}.{field}"


def level_for(percent_left):
    """The same thresholds NabBar colours its menu bar with."""
    if percent_left is None:
        return "unknown"
    if percent_left <= 0:
        return "depleted"
    if percent_left < 20:
        return "red"
    if percent_left < 50:
        return "yellow"
    return "green"


def png(width, height, pixel):
    """A minimal RGBA PNG; `pixel(x, y)` returns (r, g, b, a)."""
    rows = b"".join(
        b"\x00" + b"".join(struct.pack("4B", *pixel(x, y)) for x in range(width))
        for y in range(height)
    )

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b"")


def meter_icon(*windows):
    """Rounded bars side by side along the bottom, one per (percent_left,
    level), each filled to its % left in its level's colour. The top stays
    clear for the button's own text."""
    size, gap, height = ICON_SIZE, 10, ICON_SIZE * 2 // 5
    width = (size - gap * (len(windows) - 1)) // len(windows)
    radius = min(14, width // 2, height // 2)
    bars = []
    for i, (percent_left, level) in enumerate(windows):
        colour = LEVEL_COLOURS[level]
        bars.append((i * (width + gap), colour,
                     size - round(height * max(0.0, min(100.0, percent_left or 0)) / 100),
                     tuple(round(c * 0.22 + 0x1E * 0.78) for c in colour)))
    top = size - height

    def inside(x0, x, y):
        cx = min(max(x, x0 + radius), x0 + width - 1 - radius)
        cy = min(max(y, top + radius), size - 1 - radius)
        return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2

    def pixel(x, y):
        if y < top:
            return (0, 0, 0, 0)
        for x0, colour, fill_top, track in bars:
            if x0 <= x < x0 + width:
                if not inside(x0, x, y):
                    return (0, 0, 0, 0)
                return (*colour, 255) if y >= fill_top else (*track, 255)
        return (0, 0, 0, 0)

    return base64.b64encode(png(size, size, pixel)).decode()


def read_status():
    for path in STATUS_FILES:
        try:
            with open(path) as f:
                return json.load(f)
        except (OSError, ValueError):
            continue
    return None


def percent(value):
    return f"{round(value)}%" if value is not None else "--"


def summary_text(label, left, week):
    """'Claude\n5h 44% · 7d 80%', or just the one window a provider has."""
    if left is None:
        return f"{label}\n--"
    if week is None:
        return f"{label}\n{round(left)}% left"
    return f"{label}\n5h {round(left)}% · 7d {round(week)}%"


def provider_states(status):
    by_id = {p.get("id"): p for p in (status or {}).get("providers", [])}
    states = {}
    for pid in PROVIDERS:
        p = by_id.get(pid, {})
        left, used = p.get("percentRemaining"), p.get("percentUsed")
        week = p.get("weeklyPercentRemaining")
        level, week_level = level_for(left), level_for(week)
        label = p.get("name") or pid
        states[state_id(pid, "left")] = percent(left)
        states[state_id(pid, "used")] = percent(used)
        states[state_id(pid, "reset")] = p.get("resetText") or ""
        states[state_id(pid, "weekLeft")] = percent(week)
        states[state_id(pid, "weekReset")] = p.get("weeklyResetText") or ""
        states[state_id(pid, "status")] = p.get("status") or "unknown"
        states[state_id(pid, "summary")] = summary_text(label, left, week)
        states[state_id(pid, "level")] = level
        states[state_id(pid, "weekLevel")] = week_level
        states[state_id(pid, "icon")] = meter_icon((left, level), (week, week_level)) if week is not None else meter_icon((left, level))
    states[f"{PLUGIN_ID}.state.updatedAt"] = (status or {}).get("updatedAt", "")
    return states


def refresh_nabbar():
    subprocess.run(["/usr/bin/open", "-g", "nabbar://refresh"], check=False)


class Plugin:
    def __init__(self):
        self.sock = socket.create_connection((TP_HOST, TP_PORT))
        self.running = True
        self.sent = {}

    def send(self, message):
        self.sock.sendall((json.dumps(message) + "\n").encode())

    def handle(self, msg):
        kind = msg.get("type")
        if kind == "closePlugin" and msg.get("pluginId") == PLUGIN_ID:
            self.running = False
        elif kind == "action" and msg.get("actionId") == REFRESH_ACTION:
            refresh_nabbar()

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
                    self.handle(json.loads(line))
                except ValueError:
                    continue
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
