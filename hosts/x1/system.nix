{
  config,
  pkgs,
  lib,
  hyprland,
  self ? null,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/shared
  ];

  hyprspace.enable = true;

  hyprspace.hyprland = {
    monitorsFile = ./monitors.lua;
    hyprpaperTemplate = ../../configs/hyprpaper-default.conf;
    hyprlockTemplate = ../../configs/hyprlock-default.conf;
    hypridleConfig = ../../configs/hypridle-default.conf;
    scriptsDir = ../../scripts/hyprland;
    useHomeManager = true;
  };

  # Shell settings for the "waybar" stack — re-activated automatically when
  # hyprspace.shell = "waybar" (switch lives in modules/shared/default.nix).
  hyprspace.waybar = {
    configPath = ../../configs/waybar/config.json;
    stylePath = ../../configs/waybar/cyberpunk.css;
    scriptsDir = ../../scripts/waybar;
    useHomeManager = true;
  };

  hyprspace.services = {
    enable = true;
    openssh.enable = true;
    tlp.enable = true;
  };

  services.tailscale.enable = true;

  hyprspace.android = {
    enable = true;
    studio.enable = true;
    sdk.enable = true;
  };

  hyprspace.packages = {
    enable = true;
    base.enable = true;
    desktop.enable = true;
    dev.enable = true;
    rust.enable = true;
  };

  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  boot.loader.efi.efiSysMountPoint = "/boot";

  networking.hostName = "x1";
  networking.networkmanager.enable = true;

  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "America/Chicago";

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.bluetooth.enable = true;

  # Intel Iris Xe (Raptor Lake-P) only — no dGPU on this machine.
  services.xserver.videoDrivers = ["modesetting"];
  boot.blacklistedKernelModules = ["nouveau"];

  fonts.packages = with pkgs; [
    papirus-icon-theme
    bibata-cursors
  ];

  xdg.portal.enable = true;
  xdg.portal.wlr.enable = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.android_sdk.accept_license = true;

  programs.fish.enable = true;

  system.stateVersion = "25.11";
}
