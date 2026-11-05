# Firefox not following DMS light/dark — manual repair runbook

Firefox's profile is machine-local state that Nix does not and cannot manage, so after a
rebuild, a fresh host, or a Firefox Sync event, Firefox can stop tracking the DMS day/night
switch even though every Nix option is correct. This runbook is the ordered manual repair
procedure. It works top to bottom: each step checks one layer, fixes it if broken, and the
later steps assume the earlier ones pass.

Everything here is safe to run as the desktop user. Two rules apply to **every** step:

- **Never delete `prefs.js`, never hand-edit `extensions.json`, never click "Refresh
  Firefox".** The first orphans all extension data, the second desynchronises the add-on
  startup cache, the third wipes the profile's customizations. See
  `docs/dev/dms-theme-sync.md` Part 5 for what these cost.
- **Quit Firefox cleanly (Ctrl+Q) before touching files inside the profile**, and do not
  `pkill firefox` (on NixOS the process is named `.firefox-wrappe`, so `pkill -x firefox`
  is a no-op anyway; an unclean exit can trigger the Troubleshoot Mode prompt).

Background and the full investigation live in `docs/dev/dms-theme-sync.md`; this file is
the operator procedure only.

## Step 0 — Let Nix repair what it owns, then restart Firefox

On a hyprspace host, activation already fixes two of the most common breakages:

- the `installFirefoxMaterialFox` hook (`modules/home/dankshell.nix`) reinstalls
  `user.js` into the default profile, preserves `extensions.webextensions.uuids`, and
  re-creates the `chrome/theme-material-blue.css` symlink **if `chrome/` already exists**;
- the firefox wrapper (`modules/home/packages.nix`) locks
  `services.sync.prefs.sync.extensions.activeThemeID = false` and clears four stale
  experimental prefs at every startup.

So first:

```bash
sudo nixos-rebuild switch --flake .#<host>   # or: home-manager switch --flake .#<host>
```

Then **fully quit and restart Firefox** — `user.js` is only read at startup, and a running
instance never notices activation. If it still doesn't follow `dms ipc call theme toggle`,
continue.

## Triage

| Symptom | Likely cause | Go to |
| --- | --- | --- |
| Chrome looks stock, no Material 3 palette at all | Material Fox assets never extracted on this machine | Step 3 |
| Material Fox palette present, but stays dark (or light) when DMS flips | Wrong built-in theme active, or stale startup cache | Steps 5–6 |
| Was working, broke right after a rebuild on a machine that has `firefox.css` | Sync re-flipped the theme, or `user.js`/symlink lost | Steps 4–6 |
| Nothing in Firefox follows, portal value is also wrong | DMS itself isn't switching — fix DMS first, this runbook can't help | Step 1 |
| Broke on a fresh profile (new random suffix, "Refresh Firefox", first launch) | Assets and possibly UUID map are gone | Steps 3, 5, 6 |

## Step 1 — Confirm DMS is switching and generating `firefox.css`

```bash
dconf read /org/gnome/desktop/interface/color-scheme   # 'default' = light, 'prefer-dark' = dark
dms ipc call theme toggle; sleep 2
dconf read /org/gnome/desktop/interface/color-scheme   # must have flipped
ls -la ~/.config/DankMaterialShell/firefox.css         # must exist; mtime bumps on every toggle
```

If the dconf value doesn't flip, the problem is DMS, not Firefox — stop here and fix DMS
first. If `firefox.css` is missing, DMS's matugen hasn't run yet; log into the DMS session
once, toggle the theme, and check again.

## Step 2 — Find the real profile

The profile directory is `~/.config/mozilla/firefox/<random>.default` — **not**
`~/.mozilla` (the DMS docs are stale on this; the wrapper sets `MOZ_LEGACY_PROFILES=1`).
Either read it off `about:support` → "Profile Directory" in a running Firefox, or:

```bash
# Default=1 comes *after* Path= within its block, so capture Path and only
# print once Default=1 is seen.
PROFILE=$(awk '/^\[/{p="";next} /^Path=/{p=substr($0,6)} /^Default=1/{if(p!=""){print p;exit}}' \
  ~/.config/mozilla/firefox/profiles.ini)
PROFILE=~/.config/mozilla/firefox/$PROFILE
echo "$PROFILE"
```

All later steps use `$PROFILE`.

## Step 3 — Material Fox assets present?

```bash
ls "$PROFILE/chrome/"   # expect: userChrome.css, user-chrome.css, icons/, fonts/, ...
```

If `chrome/` is missing or only holds the symlink, Material Fox was never extracted on
this machine (the Nix hook cannot do it — the assets are third-party and the profile path
is random). Extract them:

```bash
curl -sSL -o /tmp/chrome.zip \
  https://github.com/edelvarden/material-fox-updated/releases/download/v2.0.0/chrome.zip
unzip -oq /tmp/chrome.zip -d "$PROFILE"
rm -f "$PROFILE/chrome/theme-material-blue.css"
```

Then continue to Step 4 to create the symlink. Never overwrite a user-modified
`custom_example.css`.

## Step 4 — `user.js` and the palette symlink

```bash
cat "$PROFILE/user.js"                       # expect the 3 prefs: legacyuserprofilecustomizations,
                                             # svg.context-properties, userChrome.theme-material
ls -la "$PROFILE/chrome/theme-material-blue.css"
# expect: ... -> /home/<user>/.config/DankMaterialShell/firefox.css
```

DMS's `firefox.css` is a drop-in for Material Fox's `theme-material-blue.css`; the symlink
is what puts the DMS palette on the same `--md-sys-color-*` contract. If either is
missing, re-run activation (Step 0) or fix by hand:

```bash
ln -sfn ~/.config/DankMaterialShell/firefox.css "$PROFILE/chrome/theme-material-blue.css"
```

The hook preserves the machine's `extensions.webextensions.uuids` line at the bottom of
`user.js`; if you recreate `user.js` by hand, copy that line over from `prefs.js` too.

## Step 5 — Active theme must be "System theme — auto"

Any other theme — `firefox-compact-*`, an AMO theme, a Firefox Color theme — pins
`prefers-color-scheme` and ignores the desktop entirely.

Check (Firefox running or not):

```bash
grep '"extensions.activeThemeID"' "$PROFILE/prefs.js"
# expect: user_pref("extensions.activeThemeID", "default-theme@mozilla.org");
```

Caveat: `prefs.js` and even `about:addons` read the add-on **database**; startup actually
trusts the **cache** (Step 6). If the pref disagrees, fix it with Firefox **running**:
about:addons → Themes → enable **System theme — auto**. Never hand-edit
`extensions.json`.

## Step 6 — Stale add-on startup cache

If `about:addons` says the default theme is active but Firefox still starts dark every
launch, `addonStartup.json.lz4` is stale (it records which built-in theme to start, and
nothing rewrites it when state is corrected behind its back). To confirm, decode it with
the dependency-free script in `docs/dev/dms-theme-sync.md` Part 4 and look at
`["app-builtin"]["addons"][id]["enabled"]` — the bug is
`firefox-compact-dark@mozilla.org enabled: true` while `default-theme@mozilla.org` is
false.

Fix (Firefox **closed**):

```bash
mv "$PROFILE/addonStartup.json.lz4" "$PROFILE/addonStartup.json.lz4.stale"
firefox &   # cache rebuilds from extensions.json on this start
```

This is a cache; removing it touches neither extension storage nor UUIDs. Do **not** add
this to activation — activation can run while Firefox is open.

## Step 7 — Sync lock present?

Firefox Sync syncs the theme choice and **enables** the incoming theme locally; one other
device on the account with a dark built-in theme re-breaks every machine. The lock is
delivered by the Nix wrapper; verify it:

```bash
grep activeThemeID "$(dirname "$(readlink -f "$(which firefox)")")/../lib/firefox/mozilla.cfg"
# expect: lockPref("services.sync.prefs.sync.extensions.activeThemeID", false);
```

In `about:config` the pref shows `false` with a lock icon. A plain `user_pref(..., false)`
in `user.js` is **not** enough — an incoming `null` control pref clears it mid-sync; it
must be locked.

On a **non-NixOS** Firefox, deliver the same lock with a two-file autoconfig: create
`<firefox-install>/defaults/pref/autoconfig.js` containing
`pref("general.config.filename", "mozilla.cfg");` and
`pref("general.config.obscure_value", 0);`, then `<firefox-install>/mozilla.cfg`
(beginning with a `//` comment line) containing the `lockPref(...)` line above.

Optionally, switch the *other* devices on the account to "System theme — auto" too; with
the lock it no longer matters locally, but it stops the record from fighting.

## Verify

1. Set DMS light, start Firefox normally: chrome is light.
2. `dms ipc call theme toggle`: chrome repaints dark within ~1 s, no restart. Toggle back:
   light again.
3. Non-invasive check for an already-running instance: with DMS light,
   `grep browser.theme.toolbar-theme "$PROFILE/prefs.js"` should have **no** line (the
   default `2` = system); it may read `0` while dark. A `0` that survives a switch to
   light means a theme is pinning the scheme — back to Step 5. `prefs.js` writes are
   debounced; allow up to a minute and check the mtime changed.

For a scripted acceptance test with an HTTP probe page, use the harness in
`docs/dev/dms-theme-sync.md` Part 4.

## Last resort — full ordered checklist

If it still doesn't follow, redo in order, verifying after each: Step 1 (portal flips,
`firefox.css` regenerates) → Step 3 (assets extracted) → Step 4 (`user.js` + symlink) →
Step 5 (System theme — auto, set from about:addons with Firefox running) → Step 6 (cache
moved aside) → Step 7 (lock present) → Verify. Every historically observed failure is one
of these layers; do not improvise profile surgery outside this list.
