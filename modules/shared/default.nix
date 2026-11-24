{
  lib,
  config,
  ...
}: let
  cfg = config.hyprspace;
in {
  options.hyprspace = {
    enable = lib.mkEnableOption "Enable the Hyprspace desktop experience";
    shell = lib.mkOption {
      type = lib.types.enum [
        "waybar"
        "dankshell"
      ];
      default = "waybar";
      description = ''
        Desktop shell stack: "waybar" (waybar + wofi + hyprpaper/hyprlock/hypridle + dunst)
        or "dankshell" (DankMaterialShell). One-line switch for both desktop hosts.
      '';
    };
  };

  imports = [
    ./packages.nix
    ./desktop.nix
    ./hyprland.nix
    ./waybar.nix
    ./services.nix
    ./docker.nix
    ./system.nix
    ./user.nix
    ./gaming.nix
    ./android.nix
    ./dankshell.nix
  ];

  config = lib.mkIf cfg.enable {
    documentation.man.enable = false;
    hyprspace.desktop = {
      enable = true;
      fonts.enable = true;
    };
    # THE shell switch — flip to "waybar" to restore the waybar/wofi/hypr*
    # stack on every desktop host (per-host override possible via mkForce).
    hyprspace.shell = "dankshell";
    hyprspace.hyprland.enable = true;
    hyprspace.waybar.enable = lib.mkDefault (cfg.shell == "waybar");
    hyprspace.dankshell.enable = lib.mkDefault (cfg.shell == "dankshell");
    hyprspace.services = {
      enable = true;
      openssh.enable = true;
    };
    hyprspace.system.enable = true;
    hyprspace.packages = {
      enable = true;
      base.enable = true;
      desktop.enable = true;
    };
  };
}
