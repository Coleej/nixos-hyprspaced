{
  lib,
  config,
  ...
}: let
  cfg = config.hyprspace.dankshell;
in {
  options.hyprspace.dankshell.enable = lib.mkEnableOption "DankMaterialShell shell system integration";

  # System services DankMaterialShell uses (all mkDefault so a host can
  # override). The HM side (modules/home/dankshell.nix) enables the shell
  # itself; this module only wires the system-level support.
  config = lib.mkIf cfg.enable {
    # User avatar in DMS settings
    services.accounts-daemon.enable = lib.mkDefault true;
    # Night-mode automatic location
    services.geoclue2.enable = lib.mkDefault true;
    # Battery widget backend
    services.upower.enable = lib.mkDefault true;
    # polkit itself comes from hyprspace.services; DMS provides the agent UI.
    # Deliberately no power-profiles-daemon here: the laptops (x1, thinkpad)
    # run TLP; amd-workstation enables it in its own system.nix.
  };
}
