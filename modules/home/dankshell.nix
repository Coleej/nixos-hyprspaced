{
  osConfig ? {},
  pkgs,
  lib,
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
  };
}
