{
  osConfig ? {},
  pkgs,
  lib,
  self,
  ...
}: let
  # Driven by the NixOS-side switch (hyprspace.dankshell.enable). osConfig is
  # absent for standalone HM, where this cleanly defaults to disabled. The
  # dms flake module (imported in flake.nix for non-WSL hosts) provides the
  # programs.dank-material-shell options.
  enabled = osConfig.hyprspace.dankshell.enable or false;
in {
  config = lib.mkIf enabled {
    programs.dank-material-shell = {
      enable = true;
      systemd = {
        enable = true;
        restartIfChanged = true;
      };
      enableSystemMonitoring = true;
      enableVPN = true;
      enableDynamicTheming = true;
      enableAudioWavelength = true;
      enableCalendarEvents = false;
      # settings/session otherwise unmanaged — tweak in the DMS GUI. The
      # light/dark schedule is the exception and is pinned below.
    };

    # Theme + gamma schedule. DMS has two independent automations (theme mode
    # and gamma/night mode); both are pinned to Time with shared 18:00 -> 06:00
    # hours, so one clock drives the light/dark switch and the warm tint.
    #
    # Location mode is deliberately not used: geoclue2 has no IP source in the
    # NixOS module (the daemon logs "Unknown IP source method '(null)'"), and
    # DMS's ip-api.com fallback answers 403 to Go's default User-Agent. The
    # backend therefore fell back to (0, 0), where "sunset" is 11:36 CST -- the
    # theme flipped to dark at noon. Time mode removes that dependency.
    #
    # The keys are merged into the existing session.json rather than set via
    # programs.dank-material-shell.session, because that option makes the file
    # a read-only store symlink and freezes wallpaper/dock/history edits. DMS
    # keeps ownership; the schedule is simply re-asserted on each activation.
    # The hook also seeds the persisted light/dark mode to match the schedule
    # at activation time, which is what makes a boot during the day start light
    # instead of inheriting the previous night's mode (see below).
    home.activation.manageDmsThemeSchedule = lib.hm.dag.entryAfter ["linkGeneration"] ''
      session="$HOME/.local/state/dms/session.json"

      # A fresh host has no session.json until DMS first saves one. Creating it
      # with the current configVersion keeps DMS from running migrations over
      # an empty file.
      if [ ! -f "$session" ]; then
        mkdir -p "$(dirname "$session")"
        printf '{"configVersion": 7}\n' > "$session"
      fi

      # Seed the persisted mode with what the schedule says *now*. DMS applies
      # SessionData.isLightMode at startup before/as well as the theme.auto
      # backend state, and both land asynchronously -- whichever finishes last
      # wins. Booting during the day off a session.json written last night
      # (isLightMode=false) therefore came up dark and stayed dark until 18:00,
      # because the backend only pushes on *change* and never re-sends the
      # light state it already computed. Writing the current expected value
      # makes the two agree, so the race cannot pick the wrong one.
      case "$(date +%H)" in
        0[6-9] | 1[0-7]) theme_light=true ;;
        *) theme_light=false ;;
      esac

      tmp="$(mktemp "$session.XXXXXX")"
      if ! ${pkgs.jq}/bin/jq --argjson light "$theme_light" '
        .isLightMode = $light
        | .themeModeAutoEnabled = true
        | .themeModeAutoMode = "time"
        | .themeModeShareGammaSettings = true
        | .themeModeStartHour = 18
        | .themeModeStartMinute = 0
        | .themeModeEndHour = 6
        | .themeModeEndMinute = 0
        | .nightModeEnabled = true
        | .nightModeAutoEnabled = true
        | .nightModeAutoMode = "time"
        | .nightModeStartHour = 18
        | .nightModeStartMinute = 0
        | .nightModeEndHour = 6
        | .nightModeEndMinute = 0
        | .nightModeUseIPLocation = false
      ' "$session" > "$tmp"; then
        rm -f "$tmp"
        echo "manageDmsThemeSchedule: could not parse $session" >&2
        exit 1
      fi

      # Only replace the file when the merge actually changed something, so a
      # rebuild that does not touch the schedule leaves DMS's file (and its
      # inotify watch) alone. DMS does not notice an external atomic replace,
      # so a changed schedule needs `systemctl --user restart dms` (or a
      # re-login) before the new hours are evaluated.
      if [ "$(cat "$tmp")" = "$(cat "$session")" ]; then
        rm -f "$tmp"
      else
        mv "$tmp" "$session"
      fi
    '';

    # System monitoring widget backend (dux-gop, binary still named dgop), plus
    # adw-gtk3 for dynamic GTK3
    # theming. DMS's scripts/gtk.sh locates adw-gtk3{,-dark} through
    # XDG_DATA_DIRS, copies them into ~/.local/share/themes and patches them
    # with the generated palette so GTK3 apps (Evolution) follow light/dark.
    # Without it DMS falls back to a global @import of dank-colors.css into
    # gtk-3.0/gtk.css, which GTK caches -- colours land but need an app
    # restart, and the import is removed again by any later Apply GTK Colors.
    home.packages = [
      pkgs.adw-gtk3
      pkgs.dux-gop
    ];

    # Firefox profile root. Firefox resolves its default profile through the
    # legacy root ~/.mozilla/firefox whenever that path exists, and through the
    # XDG root ~/.config/mozilla/firefox otherwise (Firefox 158+ layout). The
    # single-instance D-Bus name is derived from the resolved profile path
    # (org.mozilla.firefox.<base64 of the path>), so a root that appears *while*
    # Firefox is running changes the name every later launch asks for: nobody
    # owns it, the profile lock is still held, and Firefox answers with
    # "already running, but is not responding" instead of opening a new window
    # (SUPER+SHIFT+RETURN appeared to stop working this way — the opentracker
    # shim in modules/home/usage-tracker.nix used to create that link on
    # demand, which is exactly that flip). Create the link here, before any
    # Firefox launch, so the resolved path never changes. A real legacy
    # profile tree is left untouched; an empty XDG root is created so the link
    # can never dangle (Firefox refuses to mkdir through it).
    home.activation.ensureFirefoxProfileRoot = lib.hm.dag.entryAfter ["linkGeneration"] ''
      if [ ! -e "$HOME/.mozilla/firefox" ] && [ ! -L "$HOME/.mozilla/firefox" ]; then
        mkdir -p "$HOME/.config/mozilla/firefox" "$HOME/.mozilla"
        ln -sfn "$HOME/.config/mozilla/firefox" "$HOME/.mozilla/firefox"
      fi
    '';

    # Firefox / Material Fox. DMS regenerates
    # ~/.config/DankMaterialShell/firefox.css on every theme switch; that file
    # carries a light block plus a @media (prefers-color-scheme: dark) block,
    # so Material Fox selects the matching palette off the desktop colour
    # scheme without needing a restart.
    #
    # configs/firefox/user.js is installed into whichever profile profiles.ini
    # marks Default, because Firefox names profile directories with a random
    # suffix that Nix cannot predict. It pins only the three prefs Material Fox
    # needs. Theme selection is deliberately not pinned: the add-on DB and its
    # addonStartup.json.lz4 cache own it, and Firefox Sync is stopped from
    # overriding it by the locked
    # services.sync.prefs.sync.extensions.activeThemeID pref in
    # modules/home/packages.nix. Select "System theme -- auto" in
    # about:addons -> Themes; see docs/dev/dms-theme-sync.md.
    #
    # The hook also keeps the theme-material-blue.css symlink in place: DMS's
    # firefox.css is a drop-in for that Material Fox file, and the link is the
    # piece most likely to be lost (fresh profile, manual extract redone).
    home.activation.installFirefoxMaterialFox = lib.hm.dag.entryAfter ["linkGeneration"] ''
      # Deliberately bash builtins only. The NixOS activation environment has a
      # minimal PATH with no awk/grep/sed, so an external parser here fails the
      # whole activation with 127 and takes home-manager-cody.service down with
      # it. coreutils (install) is always present.
      ffroot="$HOME/.config/mozilla/firefox"
      if [ -f "$ffroot/profiles.ini" ]; then
        profile_rel=""
        path=""
        while IFS= read -r line; do
          case "$line" in
            "[Profile"*) path="" ;;
            Path=*) path="''${line#Path=}" ;;
            Default=1) if [ -n "$path" ]; then profile_rel="$path"; break; fi ;;
          esac
        done < "$ffroot/profiles.ini"
        if [ -n "$profile_rel" ] && [ -d "$ffroot/$profile_rel" ]; then
          # Preserve extensions.webextensions.uuids. That pref maps each
          # extension ID to the UUID naming its storage directory, and it is
          # the only pointer to that data. It is per-machine, so it cannot be
          # shipped in configs/firefox/user.js, but it must survive a rebuild:
          # if it is lost Firefox assigns fresh uuids, orphans every storage
          # directory, and all extensions silently lose their settings, tokens
          # and logins while still reporting as enabled.
          uuids=""
          for f in user.js prefs.js; do
            if [ -f "$ffroot/$profile_rel/$f" ]; then
              while IFS= read -r line; do
                case "$line" in
                  user_pref\(\"extensions.webextensions.uuids\"*) uuids="$line" ;;
                esac
              done < "$ffroot/$profile_rel/$f"
              [ -n "$uuids" ] && break
            fi
          done

          install -Dm644 "${self + /configs/firefox/user.js}" "$ffroot/$profile_rel/user.js"
          if [ -n "$uuids" ]; then
            printf '\n%s\n' "$uuids" >> "$ffroot/$profile_rel/user.js"
          fi
          # Repoint the Material Fox palette at DMS's firefox.css. ln is
          # coreutils, so it is on the activation PATH.
          if [ -d "$ffroot/$profile_rel/chrome" ] && [ -e "$HOME/.config/DankMaterialShell/firefox.css" ]; then
            ln -sfn "$HOME/.config/DankMaterialShell/firefox.css" "$ffroot/$profile_rel/chrome/theme-material-blue.css"
          fi
        fi
      fi
    '';
  };
}
