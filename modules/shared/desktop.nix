{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.hyprspace.desktop;
in {
  options.hyprspace.desktop = {
    enable = lib.mkEnableOption "Shared desktop (Wayland env, portals, fonts, GTK/Qt)";
    fonts.enable = lib.mkEnableOption "Install recommended Nerd/base fonts";
  };

  config = lib.mkIf cfg.enable {
    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1";
      MOZ_ENABLE_WAYLAND = "1";
      QT_QPA_PLATFORM = "wayland";
      GDK_BACKEND = "wayland";
      XCURSOR_THEME = "Bibata-Modern-Ice";
      XCURSOR_SIZE = "24";
    };

    # TeamViewer's GUI is only a frontend: the daemon owns
    # /var/run/teamviewerd.ipc, holds the device ID and handles the actual
    # connections. `teamviewer --daemon start` just shells out to `systemctl
    # start teamviewerd.service`, and nixpkgs ships no NixOS module for it, so
    # without this unit the client always reports "the daemon is not running"
    # (no ID, no incoming sessions). -f keeps it in the foreground so it fits
    # Type=simple. The client package is installed per-user in
    # modules/home/packages.nix (teamviewer-x11), on these same hosts only.
    systemd.services.teamviewerd = {
      description = "TeamViewer remote control daemon";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      serviceConfig = {
        ExecStart = "${pkgs.teamviewer}/bin/teamviewerd -f";
        # The daemon refuses to start if an ipc/pid file is left over from a
        # crash or a manual run (it exits 1 immediately, which just looks like
        # Restart=on-failure looping). Clear them first; only one instance of
        # this unit can exist, so there is nothing live to clobber.
        ExecStartPre = "${pkgs.coreutils}/bin/rm -f /run/teamviewerd.ipc /run/teamviewerd.pid";
        Restart = "on-failure";
        RestartSec = 5;
      };
      environment.HOME = "/root";
    };

    # greetd is a minimal Wayland-capable display/login manager; tuigreet is a
    # TUI greeter that runs inside it. `--cmd start-hyprland` launches via the
    # wrapper script that sets up XDG_CURRENT_DESKTOP, portals, etc.
    services.greetd = {
      enable = true;
      restart = true;
      # tuigreet is a full-screen TUI on tty1, but tty1 is also the kernel
      # console. Without this the greeter paints over whatever boot output is
      # already on the VT, and any console message printed after greetd starts
      # (e.g. nix-gc firing at boot via Persistent= on the timer) writes on top
      # of the login screen. This flag makes systemd own tty1 for greetd:
      # TTYVTDisallocate clears the VT first, and StandardError goes to the
      # journal instead of the screen.
      useTextGreeter = true;
      settings.default_session = {
        user = "greeter";
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd start-hyprland";
      };
    };

    # greetd runs the greeter as a dedicated, unprivileged user so the
    # kiosk-mode login screen has no extra privileges and PAM can be locked
    # down independently of the real user. isSystemUser (not isNormalUser)
    # because uid < 1000 is reserved for system accounts.
    users.users.greeter = {
      isSystemUser = true;
      uid = 400;
      home = "/var/run/greetd";
      group = "greeter";
      description = "greetd greeter user";
    };
    users.groups.greeter = {};

    xdg.portal = {
      enable = true;
      xdgOpenUsePortal = true;
      extraPortals = [pkgs.xdg-desktop-portal-gtk];
      config.common.default = [
        "hyprland"
        "gtk"
      ];
    };

    fonts.packages = lib.mkIf cfg.fonts.enable (
      with pkgs; [
        fira-code
        fira-code-symbols
        font-awesome
        nerd-fonts.fira-code
        nerd-fonts.hack
        noto-fonts
        noto-fonts-color-emoji
        ubuntu-classic
        liberation_ttf
      ]
    );
  };
}
