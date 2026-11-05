#!/usr/bin/env -S nix shell nixpkgs#python3 -c python3
"""Recover DMS dynamic light/dark theming after a rebuild.

The DMS theme-auto scheduler (backend, mode "location") resolves geolocation,
computes the current sun interval, and pushes state to the shell. After a
`nixos-rebuild switch` that restarts the dms service, the backend's geolocation
cache can hold stale or failed-resolution data, and its fallback state is
hardcoded dark -- which left the shell in dark mode even mid-day.

This script:
  1. reads the backend theme-auto state and geolocation status,
  2. busts the geolocation cache (setUseIPLocation false -> true) to force a
     fresh IP resolution and scheduler re-evaluation,
  3. syncs the running shell to the freshly computed state.

Usage: scripts/dms-theme-recover.py
"""

import glob
import json
import os
import socket
import subprocess
import time


def backend_socket() -> str:
    uid = os.getuid()
    socks = sorted(glob.glob(f"/run/user/{uid}/dms-*.sock"))
    if not socks:
        raise RuntimeError(f"no dms backend socket under /run/user/{uid}")
    return socks[0]


def rpc(method: str, params: dict | None = None) -> dict:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(backend_socket())
    try:
        s.recv(4096)  # handshake frame
    except (socket.timeout, OSError):
        pass
    msg = {"method": method}
    if params is not None:
        msg["params"] = params
    s.sendall((json.dumps(msg) + "\n").encode())
    buf = b""
    try:
        while True:
            c = s.recv(4096)
            if not c:
                break
            buf += c
    except (socket.timeout, OSError):
        pass
    s.close()
    return json.loads(buf.decode().strip())


def main() -> None:
    state = rpc("theme.auto.getState")["result"]
    loc = rpc("location.getState")["result"]
    print(
        "dms theme-auto state: "
        f"enabled={state['config']['enabled']} "
        f"mode={state['config']['mode']} "
        f"useIPLocation={state['config']['useIPLocation']} "
        f"isLight={state['isLight']} "
        f"nextTransition={state['nextTransition']}"
    )
    print(f"dms geolocation: lat={loc.get('latitude')} lon={loc.get('longitude')}")

    # Bust the stale geolocation cache and force a fresh resolution + recompute.
    rpc("theme.auto.setUseIPLocation", {"use": False})
    rpc("theme.auto.setUseIPLocation", {"use": True})
    time.sleep(3)

    state = rpc("theme.auto.getState")["result"]
    is_light = bool(state["isLight"])
    print(f"dms theme-auto state after recover: isLight={is_light} nextTransition={state['nextTransition']}")

    # Sync the running shell to the freshly computed state.
    subprocess.run(["dms", "ipc", "call", "theme", "light" if is_light else "dark"])


if __name__ == "__main__":
    main()
