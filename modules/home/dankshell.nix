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
      # settings/session intentionally unmanaged — tweak in the DMS GUI,
      # codify here later if desired.
    };

    # System monitoring widget backend (dgop), plus adw-gtk3 for dynamic GTK3
    # theming. DMS's scripts/gtk.sh locates adw-gtk3{,-dark} through
    # XDG_DATA_DIRS, copies them into ~/.local/share/themes and patches them
    # with the generated palette so GTK3 apps (Evolution) follow light/dark.
    # Without it DMS falls back to a global @import of dank-colors.css into
    # gtk-3.0/gtk.css, which GTK caches -- colours land but need an app
    # restart, and the import is removed again by any later Apply GTK Colors.
    home.packages = [
      pkgs.adw-gtk3
      pkgs.dgop
    ];

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
