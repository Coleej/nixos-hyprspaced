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
    # Without it DMS only injects a static @import into gtk-3.0/gtk.css, which
    # GTK caches -- colors land but need an app restart to refresh.
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
    # suffix that Nix cannot predict. It pins the three prefs Material Fox
    # needs and selects the follow-the-system theme -- an active
    # firefox-compact-* WebExtension theme pins prefers-color-scheme to dark
    # and overrides widget.systemUsesDarkTheme, which is what kept Firefox
    # dark no matter what the desktop did. Disabling crash-session restore
    # stops a stored session from re-applying that theme on the next start.
    home.activation.installFirefoxMaterialFox = lib.hm.dag.entryAfter ["linkGeneration"] ''
      ffroot="$HOME/.config/mozilla/firefox"
      if [ -f "$ffroot/profiles.ini" ]; then
        profile_rel=$(awk '
          /^\[/ { path=""; next }
          /^Path=/ { path=substr($0, 6) }
          /^Default=1/ { if (path != "") { print path; exit } }
        ' "$ffroot/profiles.ini")
        if [ -n "$profile_rel" ] && [ -d "$ffroot/$profile_rel" ]; then
          install -Dm644 "${self + /configs/firefox/user.js}" "$ffroot/$profile_rel/user.js"
        fi
      fi
    '';
  };
}
