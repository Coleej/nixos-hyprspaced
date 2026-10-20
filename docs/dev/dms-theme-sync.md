# DMS day/night theme sync — Firefox, Evolution, Neovim

Dev notes and implementation plan for making Firefox, Evolution and Neovim follow the
DankMaterialShell (DMS) light/dark switch. Written so a new session can pick up without
re-deriving anything. The user-facing runbook is the "DMS application theming" section of
`AGENTS.md`; this file holds the history, the mistakes, the investigation, and the plan.

- **Part 1 — Where things stand** (status, how DMS drives theming, per-app history)
- **Part 2 — Firefox investigation, 2026-10-19** (root cause found and fixed on x1)
- **Part 3 — Implementation plan** (phased work for the implementing session)
- **Part 4 — Test harness** (how to reproduce every result in this file)
- **Part 5 — Hazards and past mistakes** (read before touching a Firefox profile)

---

# Part 1 — Where things stand

## Status

| App | Follows DMS? | Notes |
| --- | --- | --- |
| Evolution (GTK3) | **Yes**, confirmed by the user | Already-running instances need a restart |
| Neovim | **Yes**, live since 2026-10-20 | fs_event watcher in `init.lua` re-sources on every switch (Phase 4, done) |
| Firefox | **Yes on x1 since 2026-10-19**, live, both directions | Hand-fixed (stale add-on startup cache, Part 2) and Nix-hardened (Phase 1, done) |

Branches, both **unmerged**:

- `~/Projects/Nix/nixos-config`: `dms-theme-sync`, 11 commits on top of `master`
  (`d3318fc` through `b884c55`). Phases 1–5 are implemented on it; Phase 6 (merge +
  amd-workstation rollout) is open.
- `~/.config/nvim` (separate repo, `origin` = `Coleej/nvim`): `dms-colorscheme`, 2 commits
  (`7c395bc`, `ea39e1f`).

The user wants to verify everything before merging. Nothing has been merged.

## How DMS drives theming

One place changes light/dark. On a theme switch DMS:

1. Writes `org.gnome.desktop.interface color-scheme` through gsettings
   (`Services/PortalService.qml` `setSystemColorScheme`). Light mode writes `'default'`,
   not `'prefer-light'`. The portal then reports `0` ("no preference", DMS's light) or `1`
   (dark). `'prefer-light'` would report `2`.
2. Writes `org.gnome.desktop.interface gtk-theme` (`Common/Theme.qml` `refreshGtkTheme`):
   `'adw-gtk3'` in light, `'adw-gtk3-dark'` in dark. Verified with `dconf read`.
3. Re-runs matugen, which regenerates per-app files: `~/.config/gtk-3.0/dank-colors.css`,
   `~/.config/DankMaterialShell/firefox.css`, `~/.config/nvim/colors/dms.lua`,
   `~/.config/nvim/lua/lualine/themes/dms.lua`, `~/.config/alacritty/dank-theme.toml`, and
   others.

`syncModeWithPortal` defaults to `true`. The DMS shell sources are in the store under
`share/quickshell/dms/` of the `dms-shell` package (`scripts/gtk.sh`, `Common/Theme.qml`,
`Common/SettingsData.qml`, `matugen/configs/*.toml`, `matugen/templates/*`). Matugen
templates support a `post_hook` (see `matugen/configs/pywalfox.toml`), but the neovim and
firefox templates do not define one.

`dms ipc call theme getMode` **lags**: called right after `theme toggle` it can still
return the old mode. Read it again a second later, or read `dconf` instead.

## Per-app history

### Evolution (done)

Home Manager was pinning every key DMS owns: `color-scheme = "prefer-dark"`,
`gtk-application-prefer-dark-theme = true`, and `gtk.theme = Adwaita-dark`. DMS writes the
first and the gtk-theme key itself, so HM re-asserting them on every activation made the
desktop fight itself (upstream `AvengeMedia/DankMaterialShell#2786`).

The fix is in `modules/home/desktop.nix`, dankshell branch only: `gtk.theme = null`,
`gtk.colorScheme = null`, and the theme name pinned with `gtk3.extraConfig.gtk-theme-name =
"adw-gtk3"`. `gtk3.extraConfig` is the only input HM merges into `settings.ini` without also
writing dconf. `pkgs.adw-gtk3` is installed in `modules/home/dankshell.nix`.

How the colours arrive: `gtk.sh` copies `adw-gtk3` and `adw-gtk3-dark` into
`~/.local/share/themes` and appends a `/* BEGIN DMS OVERRIDE */` block of `@define-color`
rules. It patches per mode: light fills `adw-gtk3/gtk.css`, dark fills
`adw-gtk3/gtk-dark.css`. HM leaves `gtk-application-prefer-dark-theme` unset, so GTK
3.24.22+ picks `gtk-dark.css` from the portal, and one static name covers both modes. The
name must stay `adw-gtk3`, because `adw-gtk3-dark` breaks light mode.

### Neovim (done, except live reload)

`matugenTemplateNeovim` defaults to `false` (`SettingsData.qml`), so `colors/dms.lua` and
the lualine theme were never generated. Separately, `init.lua` hardcoded
`tokyonight-night`. The generated `dms.lua` is a base46 colourscheme and needs the
`AvengeMedia/base46` plugin.

Fix: enabled the toggle (`dms ipc call settings set matugenTemplateNeovim true`, which is
per-machine state, not Nix), swapped the plugin to `AvengeMedia/base46`, and load `dms` with
a `tokyonight-night` fallback when the file has not been generated yet (`init.lua` around
line 685). The two generated files are gitignored in the nvim repo. Measured: dark `Normal`
bg `#101820`, light `#f7f9ff`.

### Firefox (fixed on x1; see Part 2)

The first session found these layers:

1. The Material Fox theme was not installed. **The DMS docs say `~/.mozilla/firefox`;
   Firefox 158 here uses `~/.config/mozilla/firefox/`** (`MOZ_LEGACY_PROFILES=1` is set by
   the wrapper, and `~/.mozilla` does not exist).
2. DMS's `firefox.css` is a drop-in for Material Fox's `theme-material-blue.css` (the same
   `--md-sys-color-*` contract). It carries a light block plus an
   `@media (prefers-color-scheme: dark)` block, and is symlinked into the profile's
   `chrome/`.
3. An active built-in theme (`firefox-compact-dark`) pins the chrome dark. The Sync engine
   kept re-activating it, and **a stale add-on startup cache kept it active at startup even
   after `extensions.json` was corrected**. Part 2 covers both.

Shipped in `configs/firefox/user.js`, installed by the `installFirefoxMaterialFox`
activation hook in `modules/home/dankshell.nix`: the three Material Fox prefs,
`extensions.activeThemeID = default-theme@mozilla.org`, and crash-session restore
disabled. Phase 1 revises this file; three of its prefs turned out to be wrong or useless.

---

# Part 2 — Firefox investigation, 2026-10-19

## Result

**Root cause: `addonStartup.json.lz4` in the profile was stale.** It still recorded
`firefox-compact-dark@mozilla.org enabled: true` and `default-theme@mozilla.org
enabled: false` (mtime 2026-10-18 20:25). Every other file (`extensions.json`, `prefs.js`,
`user.js`, `about:addons`) said default-theme. At startup XPIProvider trusts this cache to
decide which add-ons, themes included, to start. It does not consult `extensions.json`, and
nothing caused the cache to be rewritten. So Firefox started every session with the
compact-dark theme applied. That theme's manifest sets `"color_scheme": "dark"`
(`browser/omni.ja: chrome/browser/content/builtin-themes/dark/manifest.json`), which pins
`prefers-color-scheme` for both chrome and content and ignores the system entirely.

**Fix applied (x1, by hand, Firefox closed):** moved `addonStartup.json.lz4` aside (backup at
`/tmp/opencode/ffbackup/addonStartup.json.lz4.stale-20261018`). Firefox rebuilt it from
`extensions.json` on the next start with default-theme enabled. After that the real profile
followed DMS live in both directions (`shot-N-2.png` dark, `shot-N-3.png` light), and
`browser.theme.toolbar-theme` dropped back to its default `2` ("system").

The cache only kept the bad state alive. **Firefox Sync created it.** The add-on reconciler
log (`weave/addonsreconciler.json`, `changes`, codes 3 = enabled, 4 = disabled) shows:

```
2026-10-18 13:36:07  enable default-theme, disable compact-dark   <- the first session's fix
2026-10-18 20:20:04  enable compact-dark, disable default-theme   <- during a Sync run
2026-10-18 20:55:26  enable default-theme, disable compact-dark   <- extensions.json hand-edit
```

The 20:20:04 flip lands inside a Sync run (the `weave/failedOut/*` files are stamped
20:20:04–20:20:13), and no local action happened at that moment. The 20:55 correction was a
hand-edit of `extensions.json` with Firefox closed. It never reached `addonStartup.json.lz4`,
and that mismatch is what persisted.

How Sync can do this, from the shipped source
(`omni.ja: modules/services-sync/engines/prefs.sys.mjs`):

- `extensions.activeThemeID` is synced by default
  (`browser/omni.ja: defaults/preferences/firefox.js:634`:
  `pref("services.sync.prefs.sync.extensions.activeThemeID", true)`).
- On an incoming record, `_setAllPrefs` compares the before/after theme ID and calls
  `_maybeEnableBuiltinTheme`, which runs `addon.enable()` on a built-in theme. That changes
  real add-on state, not just a pref. All Firefox desktops on the account share **one**
  prefs record (GUID = base64 of the app ID), so the last device to upload decides the theme.
  This account has at least one other device with a dark built-in theme, plus 11 AMO themes
  that arrived with `installTelemetryInfo.source = "sync"`.
- Setting `services.sync.prefs.sync.extensions.activeThemeID = false` in `user.js` **is not
  enough**. Control prefs are synced too, and an incoming `null` for the control pref runs
  `clearUserPref`, which restores the default `true` during the same sync, before the theme
  pref is applied (control prefs are sorted first). The control pref must be **locked**
  (Phase 1).

## How the bisection went

Every run used a scratch profile and the probe page in Part 4, which reports
`prefers-color-scheme` at load and on every change to a local HTTP log. DMS was light at
each start, then toggled dark and back to light.

| Run | Profile contents | Start | Live |
| --- | --- | --- | --- |
| A | Empty profile | light | follows |
| B | Real `prefs.js` (Sync/identity/startup/session prefs stripped) + `chrome/` + shipped `user.js` | light | follows |
| C | Full copy minus extensions, storage, Sync, session, cookies/logins | light | follows |
| D | C + Firefox Color (has `theme` permission) + all 15 themes and their `extensions.json` entries | light | follows |
| E | Full copy including all extensions and storage, minus Sync/session | light | follows |
| F | E + session store, `browser.startup.page = 3` | light | follows |
| G | E + the unmodified real `prefs.js` | light | follows |
| H | G + `signedInUser.json`, `weave/`, synced-tabs, storage-sync, suggest (Sync endpoints pointed at `127.0.0.1:9`) | light | follows |
| I, K | H, located under `~/.config/mozilla/firefox/` (K also had the real `~/.cache` dir copied in) | light | follows |
| L | H without `--no-remote` | light | follows |
| J | Byte-for-byte `rsync` clone of the live profile, Sync live | light | follows |
| MAIN, M | **The real profile** (normal launch, then `--no-remote --profile <real path>`) | **dark** | **no change events at all** |
| N | Real profile after moving `addonStartup.json.lz4` aside | light | **follows** |

The clones passed apparently because `extensions.json` was path-rewritten for the copy, so
the cached add-on paths no longer matched and Firefox rebuilt the startup cache (the rebuilt
cache in the clone proves the rebuild happened; the path change is the inferred trigger).
Decoding the clone's cache next to the real one exposed the difference:

```
main  app-builtin default-theme@mozilla.org        enabled False
main  app-builtin firefox-compact-dark@mozilla.org enabled True   <- the bug
J     app-builtin default-theme@mozilla.org        enabled True
J     app-builtin firefox-compact-dark@mozilla.org enabled False
```

## Other findings from the same session

- **`widget.systemUsesDarkTheme` does not exist.** The real pref is `ui.systemUsesDarkTheme`
  (0 light, 1 dark, unset = follow the device). It backs the new light/dark/device control in
  `about:addons` (`aboutaddons-themes-mode.mjs`). The first session's experiment set a dead
  pref, which explains why it "did nothing".
- **`extensions.systemTheme.update.enabled` does not exist in Firefox 158**: there is no
  reference anywhere in either `omni.ja`. Dead pref.
- Both dead prefs are still set in the real `prefs.js`, left over from `user.js` experiments.
  A pref removed from `user.js` stays in `prefs.js`. They are harmless, but should be reset in
  `about:config` (Phase 1, step 5).
- **`toolkit.startup.max_resumed_crashes = 0` (shipped in `user.js`) is a bug.** That pref
  counts consecutive unfinished startups before Firefox offers Troubleshoot Mode, and the
  default is 3 (`browser/omni.ja: defaults/preferences/firefox.js:845`). At `0`, *any*
  unclean exit (SIGTERM during testing, OOM, power loss) triggers the "Open Firefox in
  Troubleshoot Mode?" dialog on the next start. Its "Refresh Firefox" button wipes
  extensions and prefs. This happened twice during the investigation. Remove the pref.
  (The similarly named `browser.sessionstore.max_resumed_crashes`, default 1, is a
  different pref controlling crash-session restore; Firefox's own automation sets the
  toolkit one to `-1`, meaning "never prompt".)
- **`browser.sessionstore.resume_from_crash = false` was based on a wrong theory.** Session
  restore does not carry the theme (run F). Drop it, and Sync tabs/history keep working.
- `extensions.activeThemeID` in `user.js` is at best cosmetic. The pref does not select the
  theme: the add-on DB does, and the startup cache does even more. Forcing it at every start
  can only create a pref/DB mismatch. Remove it and rely on the Sync lock plus about:addons.
- `browser.theme.toolbar-theme` / `browser.theme.content-theme` are **outputs**, written by
  `LightweightThemeConsumer.sys.mjs` (0 dark, 1 light, 2 system). They make a good probe:
  with the default theme they stay at `2` (unset in `prefs.js`) when the system is light, and
  go to `0` when it is dark. A value of `0` that survives a switch to light means a theme is
  pinning the scheme.
- The default theme follows **live** through the `(-moz-system-dark-theme)` media query.
  No launcher wrapper and no restart are needed. This rules out the old "launcher wrapper"
  idea.
- The process environment is not a factor. Firefox's wrapper sets `XDG_DATA_DIRS` with the
  gsettings schemas itself, and the scratch instances launched from the same shell behaved
  correctly.
- Firefox Color (`FirefoxColor@mozilla.com`, `theme` permission) is installed and active.
  It does **not** currently apply a theme: its `storage.local` holds only `firstRunDone` and
  `images`. If it is ever used to set a colour theme, that theme will pin the scheme the same
  way compact-dark did.
- `omni.ja` reads fine with `unzip` (it warns "bytes too long ... Compensating" and still
  extracts). Python's `zipfile` cannot read it.
- The `addonStartup.json.lz4` format is `mozLz40\0` + u32 size + one LZ4 block. A
  dependency-free decoder is in Part 4.

## Verified later (2026-10-20)

- **Material Fox is in effect on x1**: acceptance-run screenshots show the customized
  chrome (extension icons, rounded tabs, DMS palette) following DMS live.
- **The Sync lock works**: `lockPref("services.sync.prefs.sync.extensions.activeThemeID",
  false)` is in the wrapped `mozilla.cfg` (Phase 1). `clearPref()` in the same file was
  verified on a scratch profile to purge the four stale prefs from `prefs.js` at startup.
- **The acceptance test passed on the real profile** with the new wrapper: dark at dark
  start, live `change` events both directions.
- **`-safeMode` in content-process command lines is normal**, not Troubleshoot Mode. Do
  not read anything into it.
- Still unknown: whether another device on the account still uploads
  `firefox-compact-dark`. With the lock it no longer matters on these hosts (Phase 6.3
  suggests switching that device to "System theme — auto" anyway).

---

# Part 3 — Implementation plan

**Status 2026-10-20: Phases 1, 2, 4 and 5 are done** (commits `672da55`, `c3cc077` in this
repo, `ea39e1f` in the nvim repo). Phase 3 needed no work. Phase 6 (merge, amd-workstation
rollout) is open. Deviations from the original text below: Phase 1 step 5 was done with
`clearPref()` in `mozilla.cfg` instead of manual `about:config` resets (verified on a
scratch profile to purge `prefs.js` at startup); Phase 2 chose Option A; Phase 4 needed no
lualine handling because lualine is not installed.

Order matters: Phase 1 prevents the regression that cost two sessions, and the rest builds
on it. Each phase lists files, the change, and acceptance tests. Run the
**Firefox acceptance test** (Part 4) after any phase that touches Firefox.

Ground rules for every phase (see Part 5 for the reasons):

- Never delete or hand-edit `prefs.js` or `extensions.json`. Never "Refresh Firefox".
- Before touching the real profile, quit Firefox cleanly (Ctrl+Q). Then back up `prefs.js`,
  `user.js`, `extensions.json`, `addonStartup.json.lz4`, `sessionstore-backups/`.
- Activation scripts may use bash builtins and coreutils only, with `''${...}` escaping.
- After every Nix change: `nix run nixpkgs#alejandra -- .` and
  `nix eval .#nixosConfigurations.{x1,amd-workstation}.config.system.build.toplevel.drvPath`.
  Then `sudo nixos-rebuild switch --flake .#x1`, and confirm `systemctl status
  home-manager-cody.service` is not failed.

## Phase 1 — Firefox hardening (Nix)

Goal: Sync can never change the active theme on these machines, and the shipped `user.js`
contains only prefs that are correct.

1. **Lock the Sync control pref with the Firefox wrapper's autoconfig.** nixpkgs'
   `wrapFirefox` already writes `lib/firefox/mozilla.cfg` and supports `extraPrefs` (verified
   in the pinned nixpkgs: `pkgs/applications/networking/browsers/firefox/wrapper.nix`, lines
   80–85 and 575–590). In `modules/home/packages.nix`, replace the bare `firefox` entry with
   an override, applied on every desktop host (the lock does no harm on the waybar stack, and
   the Sync flip affects both stacks):

   ```nix
   (pkgs.firefox.override {
     # Firefox Sync syncs extensions.activeThemeID and, on an incoming value,
     # enables that built-in theme (services-sync/engines/prefs.sys.mjs
     # _maybeEnableBuiltinTheme). Another device on the account uses a dark
     # built-in theme, which pinned this machine dark regardless of DMS. A
     # user.js false is not enough -- an incoming null control pref clears it
     # mid-sync -- so it must be locked.
     extraPrefs = ''
       lockPref("services.sync.prefs.sync.extensions.activeThemeID", false);
     '';
   })
   ```

   `packages.nix` lists packages in a `with pkgs;` list (where `firefox` is today) and
   already has a `let` block for a derived package (`qmlls`). Follow that pattern: bind the
   override in the `let` and put the name in the list. WSL uses `packages-wsl.nix`, so it is
   unaffected. Do **not** lock `extensions.activeThemeID` itself, because XPIProvider writes it
   whenever a theme is enabled.

   Acceptance:
   - `grep activeThemeID $(dirname $(readlink -f $(which firefox)))/../lib/firefox/mozilla.cfg`
     shows the `lockPref`. The wrapper writes `mozilla.cfg` into the *wrapped* derivation's
     own `$out/lib/firefox/` (stock `mozillaCfg` content first, `extraPrefs` appended), so
     follow `readlink -f` on the `firefox` in `/etc/profiles/per-user/cody/bin` rather than
     guessing the store path.
   - In `about:config`, `services.sync.prefs.sync.extensions.activeThemeID` shows `false`
     with a lock icon.
   - Sync lock test (scratch profile, never the real one): start a scratch profile with the
     wrapper. In the Browser Console (enable `devtools.chrome.enabled` in that scratch
     profile), run
     `Services.prefs.clearUserPref("services.sync.prefs.sync.extensions.activeThemeID")`
     and confirm the value stays `false`. That is the code path an incoming `null` takes.

2. **Rewrite `configs/firefox/user.js`.** Keep:
   `toolkit.legacyuserprofilecustomizations.stylesheets`, `svg.context-properties.content.enabled`,
   `userChrome.theme-material`. Remove:
   `extensions.activeThemeID` (cosmetic, see Part 2),
   `toolkit.startup.max_resumed_crashes` (a bug, see Part 2),
   `browser.sessionstore.resume_from_crash` (wrong theory, see Part 2).
   Update the comments to match. Keep the `extensions.webextensions.uuids` NOTE block
   unchanged.

3. **Update the comment block** above `installFirefoxMaterialFox` in
   `modules/home/dankshell.nix`. It currently claims the active theme and crash restore are
   the mechanism. Replace that with: the hook installs Material Fox prefs, theme selection is
   protected by the locked Sync pref in `packages.nix`, and a pointer to this doc. Do not
   change the hook's logic. Its UUID-preservation behaviour is correct and was hard-won.

4. **Do not add automatic `addonStartup.json.lz4` repair to activation.** Activation runs
   while Firefox may be open, and the PATH has no lz4 or python. With the Sync lock in place
   the stale-cache state should not recur. Document the manual recovery instead (Phase 5).

5. **Clear the stale prefs** left in `prefs.js` by earlier experiments
   (`widget.systemUsesDarkTheme`, `extensions.systemTheme.update.enabled`,
   `toolkit.startup.max_resumed_crashes`, `browser.sessionstore.resume_from_crash`).
   Removing a pref from `user.js` does not unset it, so use `clearPref(...)` lines in the
   same `extraPrefs`/`mozilla.cfg` — no GUI needed, and it re-applies on every start.
   Never edit `prefs.js` by hand. (Implemented in `c3cc077`; verified on a scratch profile
   that the four entries disappear at startup while unrelated prefs survive.)

Phase 1 is done when: the Firefox acceptance test passes on x1, about:config shows the lock,
the four stale prefs show as default, and `home-manager-cody.service` is active.
(All verified 2026-10-20 except the about:config eyeball, which is cosmetic.)

## Phase 2 — Material Fox: verify, then decide on vendoring

1. Verify Material Fox is actually in effect on x1. `about:support` should list
   userChrome/userContent customizations, the profile's `chrome/userChrome.css` should be
   imported, and the palette should change with the DMS wallpaper/scheme. Toggle
   `userChrome.theme-material` in a scratch copy and compare screenshots. If it is **not** in
   effect, debug that first (wrong `chrome/` layout from the zip, a missing
   `theme-material-blue.css` symlink target, or a Material Fox v2.0.0 incompatibility with
   Firefox 158).
2. Decide with the user whether to keep the one-time manual extract (current state,
   documented in `AGENTS.md`) or let Nix own the assets. **Decided 2026-10-20: Option A**
   (keep manual; the hook repairs the symlink).
   - **Option A (recommended): keep it manual.** The assets are about 300 KB of third-party
     CSS/SVG, and the profile path is random per machine. The activation hook already finds
     the profile, so the manual step is a single snippet.
   - **Option B:** `pkgs.fetchzip` the release (`edelvarden/material-fox-updated` v2.0.0
     `chrome.zip`, pinned hash), and have the activation hook `cp -r` (not symlink: Firefox
     follows symlinks, but `chrome/` must stay user-writable for `custom_example.css`) into
     `<profile>/chrome/` when the directory is missing or older. Then
     `ln -sfn ~/.config/DankMaterialShell/firefox.css <profile>/chrome/theme-material-blue.css`.
     Bash builtins plus coreutils only. Never overwrite a user-modified `custom_example.css`.
3. Whichever option is chosen, the activation hook should **create the
   `theme-material-blue.css` symlink when `chrome/` exists but the link is missing or points
   elsewhere**. It is cheap, idempotent, and the most likely thing to be lost.

Acceptance: Firefox chrome visibly uses the DMS palette, and changes palette on a DMS theme
switch without a restart.

## Phase 3 — Evolution / GTK3: no work, record the limit

Already working. Running GTK3 apps cache CSS at startup, so Evolution needs a restart after
a switch. This is a GTK3 limitation, not a bug. Optional only if the user asks: a matugen
`post_hook` cannot restart Evolution safely (it may be composing mail), so do not automate
it.

## Phase 4 — Neovim live reload (nvim repo, optional)

Running nvim instances keep the old palette until `:colorscheme dms`. Implement in
`~/.config/nvim` on the `dms-colorscheme` branch, not in this repo:

- Next to the colourscheme setup in `init.lua` (around line 685), start a `vim.uv`
  `fs_event` watcher on the **directory** `stdpath('config')/colors`. Watch the directory
  because matugen may replace the file by rename, which ends a watch on the file itself. On a
  change event for `dms.lua`, debounce about 200 ms, then
  `vim.schedule(function() vim.cmd.colorscheme 'dms' end)`. Keep the handles in `_G` so
  garbage collection cannot close them. (Implemented in nvim `ea39e1f`; lualine is not
  installed here, so no statusline handling was needed. Verified headless: appending to
  `dms.lua` re-sources the scheme.)
- Guard: only when `vim.g.colors_name == 'dms'`, so a user who switched colourscheme by hand
  is left alone.
- Alternative, if the watcher proves flaky: a user matugen config with a `post_hook` that
  loops over the per-instance server sockets nvim creates at
  `$XDG_RUNTIME_DIR/nvim.<pid>.0` and runs
  `nvim --server <sock> --remote-send ':colorscheme dms<CR>'`. Check whether DMS supports
  user matugen configs before choosing this route. The DMS-shipped configs are in the store
  and cannot be edited. nvim here is 0.12.6, so `vim.uv` and the default server socket are
  available.

Acceptance: with nvim open, toggling DMS repaints nvim within about 1 s, both directions,
and a hand-picked colourscheme is not overridden.

## Phase 5 — Documentation

1. `AGENTS.md`, "DMS application theming" table: Firefox row → "live" stays correct for
   the default theme. Add "requires the default built-in theme (about:addons → Themes →
   System theme — auto); any other theme or a Firefox Color theme pins the scheme".
2. `AGENTS.md`, "Firefox profile gotchas":
   - Replace the "stored session re-applies the theme" bullet with the Sync +
     `addonStartup.json.lz4` explanation, and give the recovery: *quit Firefox, move
     `<profile>/addonStartup.json.lz4` aside, start Firefox; it rebuilds the cache from
     `extensions.json`.* Note that the file is a cache: removing it is safe and does not
     touch extension storage or UUIDs.
   - Mention that `ui.systemUsesDarkTheme` (not `widget.*`) forces light/dark, and that it
     is the about:addons appearance control.
3. `AGENTS.md` repo structure block: add `configs/firefox/user.js` and the firefox override
   in `modules/home/packages.nix`.
4. This file: move Part 2 "Not yet verified" items to "verified", or record what was found.

## Phase 6 — Merge and roll out

1. Review `git log master..dms-theme-sync` and merge to master (the user decides squash or
   merge). Merge the nvim `dms-colorscheme` branch after Phase 4, or without it if Phase 4
   is skipped.
2. **amd-workstation**: rebuild, then do the three per-host manual steps from `AGENTS.md`
   (Apply GTK Colors, the neovim template toggle, the Material Fox extract unless Phase 2
   Option B). Then run the Firefox acceptance test there. That machine syncs with the same
   account, so expect it to have whatever theme Sync last pushed. Check about:addons →
   Themes, and if the startup cache disagrees, use the Phase 5 recovery.
3. Check whether any **other** device on the account (Windows/macOS/phone Firefox) still uses
   a dark built-in theme. The lock protects these hosts either way, but switching that device
   to "System theme — auto" stops the record from fighting.

---

# Part 4 — Test harness

Everything below was used on 2026-10-19 and lives in `/tmp/opencode/ffprobe/` (gone after a
reboot; recreate from here).

**Probe page** (`index.html`). It reports to the server at load and on every change:

```html
<!doctype html><meta charset=utf-8><title>scheme-probe</title>
<style>body{font:40px sans-serif}@media (prefers-color-scheme: dark){body{background:#000;color:#fff}}</style>
<div id=o></div><script>
const tag=new URLSearchParams(location.search).get('tag')||'none';
const mq=matchMedia('(prefers-color-scheme: dark)');
function rep(ev){const v=mq.matches?'dark':'light';document.getElementById('o').textContent=tag+' '+ev+' '+v;
 fetch('/r?tag='+tag+'&ev='+ev+'&scheme='+v).catch(()=>{});}
rep('load'); mq.addEventListener('change',()=>rep('change'));
</script>
```

**Server** (`server.py`, run in the background). It appends `/r?...` hits to `results.log`.
Pass `directory=` explicitly, otherwise it serves the cwd of whatever shell launched it:

```python
import http.server, datetime, functools
class H(http.server.SimpleHTTPRequestHandler):
    def log_message(self, fmt, *a):
        if self.path.startswith('/r?'):
            open('/tmp/opencode/ffprobe/results.log','a').write(f"{datetime.datetime.now():%H:%M:%S} {self.path}\n")
http.server.ThreadingHTTPServer(("127.0.0.1", 8765),
    functools.partial(H, directory="/tmp/opencode/ffprobe")).serve_forever()
```

**Runner** (`run.sh <tag> <profiledir>`). It seeds first-run prefs, starts a scratch
instance, toggles DMS twice, and stops **only its own PID**:

```bash
tag=$1; prof=$2; mkdir -p "$prof"
cat >> "$prof/user.js" <<'J'
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.aboutwelcome.enabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("toolkit.startup.max_resumed_crashes", -1);
J
firefox --no-remote --profile "$prof" "http://127.0.0.1:8765/index.html?tag=$tag" & pid=$!
sleep 12; grim "shot-$tag-1.png"
dms ipc call theme toggle; sleep 6; grim "shot-$tag-2.png"
dms ipc call theme toggle; sleep 6; grim "shot-$tag-3.png"
kill $pid
```

A Firefox that restarts itself (after detecting changed add-ons) gets a new PID. Check
`ps -eo pid,args | grep '[p]er-user/cody/bin/firefox'` afterwards.

**Firefox acceptance test** (use it after Phases 1, 2 and 6):

1. Quit Firefox (Ctrl+Q). Set DMS to light. Start Firefox normally with
   `firefox http://127.0.0.1:8765/index.html?tag=ACCEPT` and the server running. Expect
   `ev=load&scheme=light` and light chrome.
2. `dms ipc call theme toggle`: expect `ev=change&scheme=dark` and dark chrome within about
   1 s. Toggle again and expect light.
3. `grep toolbar-theme <profile>/prefs.js`: expect no line while light (the default `2`), and
   `0` only while dark.
4. Repeat steps 1–2 with DMS dark at startup.

**Non-invasive live probe** for an already-running Firefox, needing no page: switch DMS to
light and watch `<profile>/prefs.js`. If the default theme is in effect, the
`browser.theme.toolbar-theme` line disappears (back to the default `2`); if it stays at
`0`, something is pinning dark. `prefs.js` writes are debounced, so allow up to a minute,
and confirm the file's mtime changed before concluding anything.

**Decode `addonStartup.json.lz4`** (no dependencies). Run it with
`python3 mozlz4.py <file> | python3 -m json.tool`, then look at
`["app-builtin"]["addons"][id]["enabled"]`:

```python
import sys,struct
def dec(src):
    dst=bytearray(); i=0
    while i<len(src):
        t=src[i]; i+=1; l=t>>4
        if l==15:
            while True:
                b=src[i]; i+=1; l+=b
                if b!=255: break
        dst+=src[i:i+l]; i+=l
        if i>=len(src): break
        off=src[i]|(src[i+1]<<8); i+=2; m=t&15
        if m==15:
            while True:
                b=src[i]; i+=1; m+=b
                if b!=255: break
        m+=4; s=len(dst)-off
        for k in range(m): dst.append(dst[s+k])
    return bytes(dst)
d=open(sys.argv[1],'rb').read(); assert d[:8]==b'mozLz40\0'
sys.stdout.write(dec(d[12:]).decode())
```

**Reading Firefox's own code:** `mkdir x && cd x && unzip -oq <firefox>/lib/firefox/omni.ja`,
and the same for `browser/omni.ja`. Useful files: `modules/LightweightThemeConsumer.sys.mjs`,
`modules/services-sync/engines/prefs.sys.mjs`, `defaults/preferences/firefox.js` (browser),
`greprefs.js`.

**Scratch-profile safety:** copies of the real profile contain FxA tokens, cookies and
extension API keys (`storage-sync-v2.sqlite` holds Karakeep API keys in plain text). Keep
them under `/tmp/opencode`, delete them when done, and never paste their contents into docs
or commits. Point Sync at a dead endpoint unless the test is specifically about live Sync:

```js
user_pref("identity.sync.tokenserver.uri", "http://127.0.0.1:9/");
user_pref("identity.fxaccounts.auth.uri", "http://127.0.0.1:9/");
user_pref("identity.fxaccounts.remote.root", "http://127.0.0.1:9/");
user_pref("services.sync.serverURL", "http://127.0.0.1:9/");
```

---

# Part 5 — Hazards and past mistakes

## Environment hazards

- **`pkill -x firefox` is a silent no-op.** The NixOS wrapper renames the process to
  `.firefox-wrappe`. Kill scratch instances by PID. Never `pkill` the user's browser: their
  session and the Troubleshoot Mode prompt are at stake.
- **`pkill -f <pattern>` can kill your own tool shell** if the pattern appears in its command
  line (this happened with `pkill -f ffprobe/server.py`). Use a bracket trick
  (`'ffprobe/serve[r].py'`) or a PID.
- **`firefox --screenshot` produced byte-identical PNGs** across prefs and profiles. Do not use
  it as a probe. `--headless` uses a headless look-and-feel that never follows the system.
  Use `grim` on a real window, or better, the HTTP probe above.
- **`hyprctl dispatch` is broken** under the Lua Hyprland config, and there is no `hl`
  binary, so there is no way to raise or focus a window from the shell. A window on another
  workspace cannot be captured, so ask the user, or use the `prefs.js` probe.
  `hyprctl clients -j` works and reports workspaces.
- **Home Manager activation has a minimal PATH**: no `awk`, `grep` or `sed`. Use bash
  builtins plus coreutils.
- `gsettings` in an agent shell says "No schemas installed". Use `dconf read
  /org/gnome/desktop/interface/color-scheme` instead.
- `dms ipc call theme toggle|getMode` and `dms ipc call settings get|set <key> <value>` work.
  `getMode` lags right after a toggle.

## Mistakes made, and what they cost

Recorded plainly so they are not repeated.

- **Deleted Firefox's `prefs.js` to clear stale theme state. This broke every extension.**
  `prefs.js` holds `extensions.webextensions.uuids`, the only map from extension ID to the
  `storage/default/moz-extension+++<uuid>` directory with its data. Without it Firefox mints
  fresh UUIDs and orphans all storage, while `about:addons` still reports every extension as
  active. Recovered by pairing IDs with existing storage dirs. **Never delete `prefs.js`.**
- **Hand-edited `extensions.json` to switch the theme.** This was the direct cause of the
  stale-cache bug in Part 2. `addonStartup.json.lz4` was not updated and kept winning at
  startup. Change themes in `about:addons` with Firefox running. If the state is already
  inconsistent, move `addonStartup.json.lz4` aside with Firefox closed.
- **Took "about:addons says default theme" as proof of the active theme.** about:addons reads
  the add-on DB, but startup reads the cache. Probe the behaviour (Part 4) instead of reading
  the UI.
- **Experimented with pref names nobody had checked** (`widget.systemUsesDarkTheme`,
  `extensions.systemTheme.update.enabled`). Neither exists. Grep `omni.ja` before trusting a
  pref name.
- **Shipped `toolkit.startup.max_resumed_crashes = 0` without checking what it means.** It
  makes every unclean exit prompt for Troubleshoot Mode, whose "Refresh" button destroys the
  profile's customizations.
- **The activation script used `awk`, which is not on the activation PATH.** It exited 127,
  took `home-manager-cody.service` down and failed `nixos-rebuild` with status 4. Rewritten in
  bash builtins.
- **Bash `${line#Path=}` inside a Nix indented string is a hard eval error.** It must be
  written `''${line#Path=}`.
- **x1's extension UUID map was hardcoded in the file installed on every host.** Removed.
  The hook now preserves the destination profile's own map.
- **The runbook's profile-resolution `awk` was wrong** (`Default=1` comes after `Path=`). Found
  only by running the snippet extracted from the markdown. Run doc snippets before shipping
  them.
- **Said "Evolution looks good" before any rebuild had succeeded.** That was the old config.
- **Tried the global `@import dank-colors.css` route for GTK3.** It cannot coexist with
  `adw-gtk3`: `gtk.sh apply` re-copies the theme every run, and "Apply GTK Colors" deletes the
  import.
- **Grepped for `--md-sys-color-*` in GTK CSS.** DMS injects `@define-color`, and in dark mode
  patches `gtk-dark.css`, not `gtk.css`.
- **Early Firefox tests reused one live instance** (the `pkill` no-op) and **trusted a page
  that only evaluates at load**. The HTTP probe in Part 4 reports change events and avoids
  both problems.
- **SIGTERM'd the real Firefox during testing (run M).** Together with the
  `max_resumed_crashes = 0` bug, the user got the Troubleshoot Mode prompt and had to click
  through it. Ask the user to quit Firefox cleanly before any real-profile test.
