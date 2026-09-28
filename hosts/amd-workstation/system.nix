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
    amd.enable = true;
  };

  # Shell settings for the "waybar" stack — re-activated automatically when
  # hyprspace.shell = "waybar" (switch lives in modules/shared/default.nix).
  hyprspace.waybar = {
    # amd-workstation has no internal battery; only an intermittent USB HID
    # "corsair-void-10-battery" (wireless headset) device shows up in
    # /sys/class/power_supply. Waybar's battery module throws an uncaught
    # exception (crash-looping the whole bar) whenever that device
    # disappears mid-scan, so the battery module is omitted here. See
    # hosts/thinkpad/system.nix for the laptop config with battery enabled.
    configPath = ../../configs/waybar/config-amd-workstation.json;
    stylePath = ../../configs/waybar/cyberpunk.css;
    scriptsDir = ../../scripts/waybar;
    useHomeManager = true;
  };

  hyprspace.services = {
    enable = true;
    openssh.enable = true;
  };

  services.tailscale = {
    enable = true;
  };

  # DMS control-center power-profile widget (ppd). Only enabled on this host —
  # thinkpad uses TLP instead; running both would make them fight over the
  # same sysfs governor/turbo knobs.
  services.power-profiles-daemon.enable = true;

  hyprspace.gaming = {
    enable = true;
  };

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

  networking.hostName = "amd-workstation";
  networking.networkmanager.enable = true;

  # Leave the NIC in magic-packet wake mode on shutdown so the machine can be
  # powered on remotely via Wake-on-LAN.
  networking.interfaces.enp8s0.wakeOnLan = {
    enable = true;
    policy = ["magic"];
  };

  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "America/Chicago";

  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.bluetooth.enable = true;

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
