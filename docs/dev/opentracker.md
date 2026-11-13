# OpenTracker + OpenTrackerBar — implementation plan

Dev notes and implementation plan for adding [wsmajt/opentracker](https://github.com/wsmajt/opentracker)
(CLI) and [wsmajt/OpenTrackerBar](https://github.com/wsmajt/OpenTrackerBar) (DankMaterialShell
plugin) to the `x1` host. Written 2026-11-11 from a read-only investigation of this repo and
the upstream sources at their pinned revisions. Written so a new session can implement without
re-deriving anything.

Goal: monitor **OpenCode Go plan usage** (rolling/weekly/monthly quota windows) and **OpenAI
Codex limits** from both the terminal and the existing DMS bar. Zen balance and local OpenCode
token stats come along for free (Zen) or are opt-in (local stats) in the widget.

---

## 1. Findings on this repo / host

### Layout

- Flake-based NixOS + Home Manager. Hosts defined in `flake.nix` (`hosts` attrset); this host is
  **`x1`**. Always build with `HOST="$(hostname)"` — `.#x1` here.
- Desktop shell is `hyprspace.shell = "dankshell"` (`modules/shared/default.nix`), so
  `hyprspace.dankshell.enable` is true and the DMS Home Manager module is active.
- DMS comes from the `dms` flake input: `github:AvengeMedia/DankMaterialShell/stable`, pinned in
  `flake.lock` at `43255a46ea01e9d0de1fe8ce9897c0d71566b2a8` (DMS 2.1.2). Its HM module is imported
  in `flake.nix` (`dms.homeModules.dank-material-shell`).
- `modules/home/dankshell.nix` enables `programs.dank-material-shell` and sets `systemd.enable`,
  `enableSystemMonitoring`, `enableVPN`, `enableDynamicTheming`, `enableAudioWavelength`,
  `enableCalendarEvents`. Settings/session are deliberately unmanaged.
- DMS runs as the systemd **user** service `dms.service` (`Type=notify`, `ExecStart=... dms run
  --session`). It inherits the user-manager environment; that PATH already includes
  `/etc/profiles/per-user/cody/bin` (where HM `useUserPackages` puts packages) and
  `/run/current-system/sw/bin`.

### Existing DMS plugins

- One plugin is installed: **`opencodeGoUsage`** ("OpenCode Go Usage") at
  `~/.config/dms/plugins/opencode-go-usage`, a git clone of `Coleej/opencode-go-usage`. It runs
  its own `opencode-go-usage.sh` (curl/jq) and stores settings in
  `~/.config/dms/plugin_settings.json`:
  `{"opencodeGoUsage": {"enabled": true, "showMonthly": false, ...}}`.
- `~/.config/DankMaterialShell` is now a symlink to `~/.config/dms` (DMS 2.x migration).
- `plugin_settings.json` is **mutable and unmanaged** — this is the established convention
  ("settings/session intentionally unmanaged — tweak in the DMS GUI").
- `dms plugins install <id>` pulls from the DMS registry into `~/.config/dms/plugins/<name>`;
  `dms plugins lock` / `restore` exist but are imperative. Not used here — see §3.

### The DMS HM module already supports declarative plugins

From the pinned source (`dms/distro/nix/options.nix` + `home.nix`):

```nix
programs.dank-material-shell.plugins.<name> = {
  enable = true;                     # default true
  src = <package or path>;           # required; symlinked to ~/.config/dms/plugins/<name>
  settings = { };                    # optional; only written when non-empty
};
```

- The plugin dir entry is `xdg.configFile."dms/plugins/${name}"` → a store symlink.
- `plugin_settings.json` is only managed when any declared plugin has non-empty `settings`
  (`managePluginSettings` defaults to `hasPluginSettings`). Declaring the plugin with **no
  settings** leaves `plugin_settings.json` untouched, preserving `opencodeGoUsage`.
- DMS discovers plugins by scanning the plugins dir for `plugin.json`; the manifest `id` (not the
  directory name) keys the settings. The shell only loads a plugin when
  `getPluginSetting(id, "enabled", false)` is true — so **enabling is a GUI step** unless
  `plugin_settings.json` is managed (we are deliberately not managing it).

### Tooling available

- nixpkgs `go` = **1.27.3** (CLI needs `go 1.26.3` — fine).
- nixpkgs `opentracker` (1.0) is an **unrelated BitTorrent tracker**. There is no package for
  wsmajt/opentracker anywhere in the pinned inputs → package from source.
- `opencode` 2.2.5 installed at `/etc/profiles/per-user/cody/bin/opencode`.
- `codex` is **not installed**; `~/.codex` does not exist.
- `gnome-keyring-daemon` (Secret Service) is running and unlocked via PAM (`hyprspace.services`,
  `security.pam.services.greetd.enableGnomeKeyring`) — required by opentracker's credential store.
- OpenCode is already authenticated locally (`~/.local/share/opencode/auth.json` exists), but that
  is the CLI's own credential; opentracker needs its own console-session cookie (see §5).

---

## 2. Verified upstream facts

### opentracker CLI

- Go module (`main.go` + `cmd/{fetch,login,stats,reset,version,root}.go`). Upstream `Makefile`:
  `go build -ldflags "-X main.version=$(VERSION) -s -w"`; `VERSION ?= 1.5.1`.
- Latest tag: **`v1.5.1`** (`1517b7300c2d4c185e98e686a2c8673dc9994085`). `go.mod` requires
  `go 1.26.3`.
- Commands (confirmed in source, not just README):
  - `opentracker login opencode` — opens `https://opencode.ai/console/login`, then imports the
    browser's `__Host-console_session` cookie into the OS keyring, verifies it against
    `/console/api/orgs`, selects a workspace, writes only `workspace` + `credentialId` to
    `~/.config/opentracker/config.json`. No plaintext fallback. (The OpenTrackerBar README says
    `login opencode-go`; that is stale — the real subcommand is `opencode`. Go and Zen share
    the login.)
  - `opentracker login codex` — shells out to **`codex login`** (requires the Codex CLI); tokens
    land in `~/.codex/auth.json` (honours `CODEX_HOME`). Alternative:
    `OPENTRACKER_CODEX_ACCESS_TOKEN` + `OPENTRACKER_CODEX_ACCOUNT_ID`.
  - `opentracker fetch opencode-go` — OpenCode Go quota: `rolling`, `weekly`, `monthly`
    (`usedPercent`, `resetsAt`, `windowMinutes`). Cached 90 s; `--force` skips.
  - `opentracker fetch codex` — `plan`, `primary` (session), `secondary` (weekly),
    `creditsRemaining`, optional `resetCredits`. Bypasses cache.
  - `opentracker fetch opencode-zen` — dollar balance, same OpenCode login.
  - `opentracker fetch claude` — reads `~/.claude/.credentials.json`; not needed here.
  - `opentracker stats opencode` — delegates to `opencode stats --json --standalone --days 0`
    (local token/session counts, distinct from quota); 5-minute cache. Resolves `opencode` via
    `OPENCODE_BIN`, then `PATH`, then `~/.bun/bin`, `~/.local/bin`, `/usr/local/bin`.
  - `opentracker version`.
- Runtime deps: OS keyring (D-Bus Secret Service), network, optionally `codex` / `opencode`
  binaries for the flows above. No daemon, no service, no system integration.
- Files it owns (mutable runtime state, outside Nix): `~/.config/opentracker/config.json`,
  `~/.cache/opentracker/`, keyring entries.

### OpenTrackerBar plugin

- DMS widget plugin, `plugin.json`:
  ```json
  { "id": "openTrackerBar", "version": "1.4.0", "type": "widget",
    "component": "./OpenTrackerBarWidget.qml", "settings": "./OpenTrackerBarSettings.qml",
    "permissions": ["process", "settings_read", "settings_write"] }
  ```
- Invokes `["opentracker", "fetch", <target>]` via Quickshell `Process` — **bare command name, so
  `opentracker` must be on the DMS process PATH**. Also calls `dms notify` for alerts. Local-stats
  path calls `["opentracker", "stats", "opencode"]`.
- Refresh: `refreshInterval` plugin setting in ms, default **120000** (options 60 s…30 min),
  manual refresh adds `--force`. Each provider tracks its own last-success; stale after 2×interval.
- Bar display: pin Go / Zen / Codex / Claude independently in the widget popout. With nothing
  pinned, `normalizeBarSources` defaults to `["opencode-go", "opencode-zen", "codex"]`.
  `barProvider` is a legacy setting superseded by `barSources`.
- No git tags upstream; pin a commit. `main` HEAD at investigation time:
  `a2fcb5c0e788185ac2d2828e4ed42de78c87073d` (plugin 1.4.0).
- Upstream install path is `dms plugins install openTrackerBar` (registry). Not used — see §3.

---

## 3. Implementation

Verified before writing this plan: the CLI builds with `buildGoModule` and runs
(`opentracker version` → `1.5.1`; unauthenticated `fetch` fails with the documented
"not configured" errors). Hashes below were resolved against the pinned nixpkgs.

### 3.1 `modules/home/packages.nix` — package the CLI

Add a `let` binding and two list entries to `home.packages`:

```nix
opentracker = pkgs.buildGoModule rec {
  pname = "opentracker";
  version = "1.5.1";
  src = pkgs.fetchFromGitHub {
    owner = "wsmajt";
    repo = "opentracker";
    rev = "v${version}";
    hash = "sha256-uhEY8V0utfMOFZbU/hW9rSw/LIGFOEUiE5OgsVz1lL4=";
  };
  vendorHash = "sha256-h2KZAB3pYdJAPotdj7YxF9P39EEk5OyCef2Esq2SWBA=";
  ldflags = ["-s" "-w" "-X" "main.version=${version}"];
};
```

…and add `opentracker` and `codex` (`pkgs.codex`, nixpkgs 0.167.0) to the `home.packages` list.
`codex` is required because `opentracker login codex` shells out to `codex login`; the widget's
Codex tab needs the resulting `~/.codex/auth.json`.

Why `packages.nix`, not `dankshell.nix`: the CLI is useful from a plain terminal regardless of
which desktop shell is active (`hyprspace.shell` can flip back to `"waybar"`), and repo convention
puts user packages here.

### 3.2 `modules/home/dankshell.nix` — declare the plugin

Inside the existing `programs.dank-material-shell = { ... };` block (which is already gated on
`osConfig.hyprspace.dankshell.enable`):

```nix
plugins.openTrackerBar = {
  src = pkgs.fetchFromGitHub {
    owner = "wsmajt";
    repo = "OpenTrackerBar";
    rev = "a2fcb5c0e788185ac2d2828e4ed42de78c87073d";
    hash = "sha256-2yI30jIWn2fdiTU8LkQO2AzbJEBXn/iF8x4vOmuAE+E=";
  };
};
```

No `settings` → `managePluginSettings` stays false → `plugin_settings.json` (including the
`opencodeGoUsage` entry) is untouched. The plugin appears in DMS's plugin directory as
`~/.config/dms/plugins/openTrackerBar` (store symlink).

### 3.3 `AGENTS.md`

One line in the DMS section noting OpenTrackerBar is Nix-managed (`modules/home/dankshell.nix`)
and that login/enablement are manual GUI/terminal steps. Keep it short.

### 3.4 What is intentionally *not* done

- No `dms plugins install` (imperative registry install, unpinned), no AUR, no `curl | sh`.
- No flake input changes; no unrelated config edits.
- Not managing `settings.json` / `plugin_settings.json` — the bar layout, widget placement, and
  enabled flags stay GUI-owned, matching the existing convention. (This also avoids clobbering
  the `opencodeGoUsage` settings.)
- The existing `opencodeGoUsage` plugin is left installed and enabled. It overlaps with
  OpenTrackerBar (both show Go usage); disable/remove it in the GUI afterwards if desired.

---

## 4. Validation

```bash
HOST="$(hostname)"                       # must be x1
nix run nixpkgs#alejandra -- .           # formatting
sudo nixos-rebuild dry-activate --flake .#$HOST   # eval/type check (or: nixos-rebuild build)
home-manager switch --flake .#$HOST      # HM-only, no system rebuild, no session restart
opentracker version                      # expect: opentracker 1.5.1
opentracker fetch opencode-go            # expect "not configured" until login (see §5)
opentracker fetch codex                  # expect "not configured" until login
dms plugins list                         # expect openTrackerBar listed (not in registry)
ls -l ~/.config/dms/plugins/openTrackerBar   # expect symlink into /nix/store
```

Augment evaluation: `nix eval .#nixosConfigurations.x1.config.home-manager.users.cody.programs.dank-material-shell.plugins.openTrackerBar.src` (and the `home.packages` list) to confirm both wiring paths.

DMS watches the plugin directory, so the plugin should appear without a restart. If it does not,
ask before `systemctl --user restart dms` — that restarts the shell/bar UI.

Do not claim the widget renders until it is seen in the running session. After login, verify the
data itself in a terminal first (`opentracker fetch opencode-go | jq`, same for `codex`); the
widget is only a consumer of those JSON payloads.

---

## 5. Remaining manual steps (authentication)

These are user actions; do not automate cookie import or reuse credentials across applications
without explicit approval. Never print cookies/tokens or put them in Nix, git, argv, or logs.

1. **OpenCode Go** — `opentracker login opencode`
   - Opens `opencode.ai/console/login`; sign into the intended account in Firefox; press Enter.
   - Imports the console session cookie into gnome-keyring, verifies the workspace, writes
     `~/.config/opentracker/config.json` (workspace + credentialId only, no cookie).
   - Requires the keyring to be unlocked (it is, via PAM); failure is a hard error, never a
     plaintext fallback.
2. **Codex** — `opentracker login codex`
   - Runs the Codex CLI login flow (browser OAuth) → `~/.codex/auth.json`.
   - `codex` comes from `pkgs.codex` added in §3.1. Alternative for automation only:
     `OPENTRACKER_CODEX_ACCESS_TOKEN` (+ optional `OPENTRACKER_CODEX_ACCOUNT_ID`) in the
     environment — out of scope here.
3. **DMS** — Settings → Plugins → **OpenTrackerBar** → enable (approve the `process` permission
   if prompted), then add the widget to a DankBar. Default bar pins are Go + Zen + Codex; unpin
   Zen in the popout if only quota should show. Refresh interval defaults to 120 s (configurable
   in plugin settings). Optional: enable the local `opentracker stats opencode` summary in the
   widget's preferences (requires the OpenCode CLI on PATH — already present).

Note: the widget's default 120 s refresh runs `fetch codex` with no cache, i.e. a request every
2 minutes. If that is too chatty for the provider's rate limits, raise the interval (5–15 min) in
the plugin settings.

---

## 6. Upstream revisions pinned

| Component | Revision | Hash |
| --- | --- | --- |
| opentracker | tag `v1.5.1` (`1517b7300c2d4c185e98e686a2c8673dc9994085`) | `sha256-uhEY8V0utfMOFZbU/hW9rSw/LIGFOEUiE5OgsVz1lL4=` (src), `sha256-h2KZAB3pYdJAPotdj7YxF9P39EEk5OyCef2Esq2SWBA=` (vendor) |
| OpenTrackerBar | commit `a2fcb5c0e788185ac2d2828e4ed42de78c87073d` (plugin 1.4.0) | `sha256-2yI30jIWn2fdiTU8LkQO2AzbJEBXn/iF8x4vOmuAE+E=` |

---

## 7. Rollback

Reverse the three edits (§3.1–3.3) and run `home-manager switch --flake .#$HOST`:

- `opentracker` / `codex` disappear from the user profile; the plugin symlink under
  `~/.config/dms/plugins/` is removed and the widget drops out of DMS.
- `plugin_settings.json`, `settings.json`, the `opencodeGoUsage` plugin, and the bar layout are
  untouched by this integration.
- Residual, non-Nix state if you also want to purge credentials:
  `~/.config/opentracker/`, `~/.cache/opentracker/`, `~/.codex/auth.json` (if only used for
  OpenTracker), the gnome-keyring entries created by `login opencode`, and the
  `openTrackerBar` key in `~/.config/dms/plugin_settings.json` if the GUI wrote one.

---

## 8. Open questions / risks

- **PATH assumption.** The widget resolves `opentracker` by name. The DMS user service inherits a
  PATH containing `/etc/profiles/per-user/cody/bin` today; if DMS is ever launched from a
  session with a smaller PATH, the widget will report "OpenTracker CLI is not installed". Fix in
  that case: either keep the package in `home.packages` (current plan) or add an explicit
  `Environment=PATH=...` to `systemd.user.services.dms` via HM.
- **OpenCode browser-cookie import** relies on kooky reading the Firefox cookie DB. The profile
  here lives under `~/.config/mozilla/firefox` (see AGENTS.md); kooky v0.2.9 only scans
  `~/.mozilla/firefox` (plus snap/esr variants), so the import failed with "no OpenCode session
  cookies found in any browser" until `~/.mozilla/firefox` was symlinked to the XDG profile root.
  The `opentracker` on PATH is now a `writeShellScriptBin` wrapper
  (`modules/home/usage-tracker.nix`) that creates that shim on demand before exec'ing the real
  CLI, so there is no per-host manual step. Run `opentracker login opencode -v` to confirm the
  detected profile.
- **Upstream churn.** OpenTrackerBar has no tags and no releases; the pinned commit is `main`
  HEAD as of 2026-11-11. Bump deliberately and re-check the manifest id stays `openTrackerBar`.
- **Rate limits.** Codex fetches bypass opentracker's 90 s cache; the widget's default 2-minute
  interval is upstream's default but is the main tunable.
