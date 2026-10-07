#!/usr/bin/env -S nix shell nixpkgs#python3 -c python3
"""Preflight, backup and migration-state report for moving a machine to opencode v2.

Run this by hand on every machine, either just before or just after
`nixos-rebuild switch` with v2 enabled. It never edits anything and never
migrates anything -- it only inspects, backs up, and reports. v2 performs the
actual data migration itself, on first launch.

Why a manual script rather than activation logic:

  * v2's v1->v2 migration is ONE-WAY. Once it runs there is no supported path
    back to 1.18.31 with your sessions intact, so you want a backup that
    predates it.
  * Migrating while another opencode process holds opencode.db is the exact
    condition that produced "Unexpected server error. Check server logs for
    details." on v2 -- two builds writing one SQLite file with different
    schemas. This refuses to run in that state.

Usage:
    scripts/opencode-v2-migrate.py              # preflight + backup + report
    scripts/opencode-v2-migrate.py --check-only # inspect, write nothing
    scripts/opencode-v2-migrate.py --force      # proceed even if oc is running

Exit status is 0 when nothing needs attention, 1 when a blocking problem was
found, so it is usable as a gate in a larger provisioning script.

The python3 shebang is deliberate: python3 is only in systemPackages behind
`dev.enable`, and the sqlite3 CLI is not installed at all, so the script
sources its interpreter from the store instead of assuming either.
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path

DATA_DIR = Path.home() / ".local" / "share" / "opencode"
CONFIG_DIR = Path.home() / ".config" / "opencode"
DB = DATA_DIR / "opencode.db"
LEGACY_DB = DATA_DIR / "opencode-stable.db"
CONFIG_JSON = CONFIG_DIR / "opencode.json"

# v2 records its one-way migration here.
MIGRATION_KEY = "migration.v1-v2"

V1 = "1"
V2 = "2"
UNKNOWN = "?"


# ---------------------------------------------------------------- detection


def detect_build() -> tuple[str, str | None]:
    """Return (major_version, raw_version_string) for the opencode on PATH."""
    exe = shutil.which("opencode")
    if exe is None:
        return UNKNOWN, None

    try:
        proc = subprocess.run(
            [exe, "--version"],
            stdin=subprocess.DEVNULL,  # without this the TUI starts and hangs
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        return UNKNOWN, f"<could not run --version: {exc}>"

    out = (proc.stdout or proc.stderr).strip()
    if not out:
        return UNKNOWN, None

    # v1 prints a bare "1.18.31"; v2 prints "opencode v2.0.24".
    match = re.search(r"v?(\d+)\.\d+\.\d+", out)
    return (match.group(1) if match else UNKNOWN), out


def running_pids() -> list[int]:
    """PIDs of live opencode processes, excluding this script and probes."""
    me = os.getpid()
    pids = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        if pid == me:
            continue
        try:
            cmdline = (entry / "cmdline").read_bytes().split(b"\0")
        except OSError:
            continue
        # argv[0] is the wrapper bash script for nix-built binaries, so match on
        # any argument, but skip our own --version probe reaped above.
        if any(arg.endswith(b"opencode") for arg in cmdline if arg):
            pids.append(pid)
    return sorted(pids)


# ------------------------------------------------------------------ backup


def make_backup() -> Path | None:
    """Timestamped `cp -a` equivalent of the whole data dir."""
    if not DATA_DIR.is_dir():
        return None
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    dest = DATA_DIR.with_name(f"{DATA_DIR.name}.backup-{stamp}")
    shutil.copytree(DATA_DIR, dest, symlinks=True)
    return dest


# --------------------------------------------------------------- migration


def migration_phase() -> tuple[str | None, str | None]:
    """Read kv['migration.v1-v2'] -> (phase, raw_value). Phase is None if absent."""
    if not DB.is_file():
        return None, None
    try:
        # Read-only, and immutable=1 would be too strict while a writer holds
        # the WAL. mode=ro at least refuses to create the file for us.
        con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=10)
    except sqlite3.Error:
        return None, None
    try:
        row = con.execute(
            "SELECT value FROM kv WHERE key = ?", (MIGRATION_KEY,)
        ).fetchone()
    except sqlite3.Error:
        return None, None
    finally:
        con.close()

    if row is None:
        return None, None
    raw = row[0]
    try:
        return json.loads(raw).get("phase"), raw
    except (json.JSONDecodeError, AttributeError):
        return None, raw


# ------------------------------------------------------------------ config


def check_provider_shape() -> list[str]:
    """Report providers still in the v1 shape that v2 rejects.

    v2 nests connection settings under `options` beside the provider's `npm`
    package. A v1-era block with `baseURL` / `apiKey` at the provider's top
    level is rejected by v2's ProviderConfig, which sets
    additionalProperties: false.
    """
    problems: list[str] = []
    if not CONFIG_JSON.is_file():
        return problems

    try:
        config = json.loads(CONFIG_JSON.read_text())
    except json.JSONDecodeError as exc:
        return [f"{CONFIG_JSON} is not valid JSON: {exc}"]

    for name, spec in (config.get("provider") or {}).items():
        if not isinstance(spec, dict):
            continue
        stray = [k for k in ("baseURL", "apiKey") if k in spec]
        if stray:
            problems.append(
                f"provider.{name} has v1-era top-level {', '.join(stray)}; "
                f"v2 wants these nested under provider.{name}.options"
            )
    return problems


def is_hm_managed(path: Path) -> bool:
    """True if the config file is a symlink into the nix store (HM-managed)."""
    return path.is_symlink() and "/nix/store/" in os.readlink(path)


# -------------------------------------------------------------------- main


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Preflight and back up before/after moving to opencode v2."
    )
    parser.add_argument(
        "--check-only",
        action="store_true",
        help="inspect and report, but do not write a backup",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="continue even if an opencode process appears to be running",
    )
    args = parser.parse_args()

    blocking = False

    # -- running processes: the concurrent-writer hazard -------------------
    pids = running_pids()
    if pids:
        print("BLOCKER  opencode is running (pid(s): "
              f"{', '.join(map(str, pids))})")
        print("         Two builds writing one opencode.db with different schemas")
        print("         is what produces 'Unexpected server error'. Quit every")
        print("         opencode session and any `opencode serve --service`, then")
        print("         re-run. Override with --force if you are certain.")
        if args.force:
            print("warn     --force given, continuing anyway (backup may be")
            print("         inconsistent if a writer is mid-transaction)")
        else:
            blocking = True
    else:
        print("ok       no opencode process running")

    # -- installed build ---------------------------------------------------
    major, raw = detect_build()
    label = {V1: "v1 (1.x)", V2: "v2 (2.x)", UNKNOWN: "unrecognised"}[major]
    print(f"info     opencode on PATH: {raw or 'not found'}  [{label}]")

    # -- data dir ---------------------------------------------------------
    if not DATA_DIR.is_dir():
        print(f"ok       no data dir at {DATA_DIR} (fresh machine, nothing to migrate)")
    else:
        size = sum(f.stat().st_size for f in DATA_DIR.rglob("*") if f.is_file())
        print(f"info     data dir {DATA_DIR} ({size / 1e6:.1f} MB)")

        if LEGACY_DB.is_file():
            print("note     legacy opencode-stable.db present -- the nixpkgs v1")
            print("         wrapper uses that filename when it exists. v2 ignores")
            print("         it. Harmless, but do not delete it before migrating.")

        phase, raw_mig = migration_phase()
        if phase == "completed":
            print("ok       v1->v2 data migration already completed"
                  + (f" ({raw_mig})" if raw_mig else ""))
        elif phase:
            print(f"warn     migration phase is {phase!r}, not 'completed'")
        else:
            print("info     v1->v2 migration has NOT run yet")
            print("         It runs automatically on v2's first launch, and it is")
            print("         one-way. That is why the backup below matters.")

    # -- config ------------------------------------------------------------
    if CONFIG_JSON.is_file():
        origin = "home-manager managed (symlink into /nix/store)" \
            if is_hm_managed(CONFIG_JSON) else "local file"
        print(f"info     config {CONFIG_JSON} [{origin}]")
        if is_hm_managed(CONFIG_JSON):
            print("         Do not edit it directly -- change modules/home/opencode.nix")
            print("         and rebuild, or the next activation reverts your edit.")
        for problem in check_provider_shape():
            blocking = True
            print(f"BLOCKER  {problem}")
    else:
        print(f"info     no {CONFIG_JSON}")

    # -- backup ------------------------------------------------------------
    if blocking:
        print("\nNo backup taken (fix the blockers above first, or pass --force).")
        return 1

    if args.check_only:
        print("\ncheck-only: no backup written.")
        return 0

    if DATA_DIR.is_dir():
        dest = make_backup()
        if dest is not None:
            print(f"ok       backup written to {dest}")
            print("         Restore with: rm -rf ~/.local/share/opencode && "
                  f"cp -a {dest} ~/.local/share/opencode")
        else:
            print("error    backup failed")
            return 1
    else:
        print("\nnothing to back up.")

    # -- next steps --------------------------------------------------------
    print("\nNext:")
    if major == V1:
        print("  1. nixos-rebuild switch      # with v2 enabled")
        print("  2. start opencode once       # triggers the one-way migration")
        print("  3. re-run this script        # expect 'migration already completed'")
    else:
        print("  opencode on PATH is already v2. Nothing left to do.")

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\ninterrupted", file=sys.stderr)
        sys.exit(130)
