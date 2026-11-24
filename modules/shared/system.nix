{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.hyprspace.system;
in {
  options.hyprspace.system = {
    enable = lib.mkEnableOption "Enable shared system/kernel performance settings";
    kernelPackages = lib.mkOption {
      type = lib.types.nullOr lib.types.unspecified;
      default = pkgs.linuxPackages_zen;
      description = "Kernel packages to use. Defaults to Zen kernel. Set to null to use system default.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelPackages = cfg.kernelPackages;

    services.fstrim = {
      enable = true;
      interval = "weekly";
    };

    zramSwap = {
      enable = true;
      algorithm = "zstd";
    };

    nix.settings.auto-optimise-store = true;
    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
      # The timer is Persistent=, so a weekly run missed while the machine was
      # off fires as soon as the system boots -- right when greetd is drawing
      # tuigreet on tty1 (seen on x1: GC started at 05:09:00, greetd at
      # 05:09:01). A delay keeps collector output off the login screen.
      randomizedDelaySec = "15m";
    };

    powerManagement = {
      enable = true;
      # TLP manages CPU frequency scaling when enabled; avoid conflict by not
      # setting a governor in that case.
      cpuFreqGovernor = lib.mkIf (!config.services.tlp.enable) "performance";
    };
  };
}
