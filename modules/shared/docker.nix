{
  config,
  lib,
  ...
}: let
  cfg = config.hyprspace.docker;
in {
  options.hyprspace.docker = {
    enable = lib.mkEnableOption "Docker daemon and CLI";

    mode = lib.mkOption {
      type = lib.types.enum [
        "rootless"
        "rootful"
      ];
      default = "rootless";
      description = ''
        Docker daemon mode. "rootless" runs a per-user daemon inside a user
        namespace (no docker group, data in ~/.local/share/docker); "rootful"
        runs a system daemon and adds the primary user to the docker group.
        Rootless cannot bind host ports below 1024 or run swarm overlay
        networks; switch to "rootful" for those.
      '';
    };

    extraPackages = lib.mkOption {
      type = with lib.types; listOf package;
      default = [];
      description = ''
        Additional container CLI packages to install (e.g. lazydocker, dive).
        The `docker` package itself already bundles the compose and buildx
        CLI plugins.
      '';
    };

    autoPrune = {
      enable = lib.mkEnableOption "Automatic pruning of unused Docker objects (rootful mode only)";
      dates = lib.mkOption {
        type = lib.types.str;
        default = "weekly";
        description = "systemd calendar expression for the prune timer (rootful mode only).";
      };
      flags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "-af"
          "--volumes"
        ];
        description = "Flags passed to `docker system prune` (rootful mode only).";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker = {
      enable = cfg.mode == "rootful";
      autoPrune = {
        enable = cfg.mode == "rootful" && cfg.autoPrune.enable;
        dates = cfg.autoPrune.dates;
        flags = cfg.autoPrune.flags;
      };
    };

    virtualisation.docker.rootless = {
      enable = cfg.mode == "rootless";
      setSocketVariable = cfg.mode == "rootless";
    };

    # Rootful only: membership in the docker group is root-equivalent, so
    # rootless mode needs no group at all. List merging appends this to the
    # groups set in modules/shared/user.nix.
    users.users."${config.hyprspace.user.name}".extraGroups =
      lib.optional (cfg.mode == "rootful") "docker";

    environment.systemPackages = cfg.extraPackages;
  };
}
