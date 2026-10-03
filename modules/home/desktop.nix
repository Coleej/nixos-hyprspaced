{
  config,
  pkgs,
  lib,
  self,
  hostName,
  osConfig ? {},
  ...
}: let
  monitorsFile =
    {
      thinkpad = self + /hosts/thinkpad/monitors.lua;
      amd-workstation = self + /hosts/amd-workstation/monitors.lua;
      x1 = self + /hosts/x1/monitors.lua;
    }
    .${
      hostName
    } or (throw "No monitors.lua for host: ${hostName}");

  # amd-workstation has no internal battery; only an intermittent USB HID
  # "corsair-void-10-battery" (wireless headset) device shows up in
  # /sys/class/power_supply. Waybar's battery module throws an uncaught
  # exception (crash-looping the whole bar) whenever that device
  # disappears mid-scan, so its config omits the battery module. thinkpad
  # is a real laptop and keeps battery in its config.
  waybarConfigFile =
    {
      thinkpad = self + /configs/waybar/config.json;
      amd-workstation = self + /configs/waybar/config-amd-workstation.json;
      x1 = self + /configs/waybar/config.json;
    }
    .${
      hostName
    } or (throw "No waybar config.json for host: ${hostName}");

  # Active desktop shell stack from the NixOS-side switch. Read by the Lua
  # Hyprland config via ~/.config/hypr/shell.lua. "waybar" when unset.
  shellName = osConfig.hyprspace.shell or "waybar";
in {
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = true;
  };

  dconf.settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";

  programs.alacritty = {
    enable = true;
  };

  programs.wofi = {
    # DMS spotlight replaces wofi in the "dankshell" stack.
    enable = shellName != "dankshell";
    settings = {
      allow_markup = true;
      insensitive = true;
    };
  };

  programs.hypr-binds = {
    enable = true;
    settings = {
      launcher = {
        app = "wofi";
      };
    };
  };

  home.file = {
    ".config/hypr/hyprland.lua" = {
      source = self + /configs/hyprland.lua;
      force = true;
    };
    ".config/hypr/autostart.lua" = {
      source = self + /configs/autostart.lua;
      force = true;
    };
    ".config/hypr/window-rules.lua" = {
      source = self + /configs/window-rules.lua;
      force = true;
    };
    ".config/hypr/animations.lua" = {
      source = self + /configs/animations.lua;
      force = true;
    };
    ".config/hypr/keybinds.lua" = {
      source = self + /configs/keybinds.lua;
      force = true;
    };
    ".config/hypr/monitors.lua" = {
      source = monitorsFile;
      force = true;
    };
    # Single source of truth for the active shell stack inside the Lua
    # Hyprland config (keybinds.lua / autostart.lua / hyprland.lua).
    ".config/hypr/shell.lua".text = ''
      return "${shellName}"
    '';
    ".config/waybar/config" = {
      source = waybarConfigFile;
      force = true;
    };
    ".config/waybar/style.css" = {
      source = self + /configs/waybar/default.css;
      force = true;
    };
    ".config/wofi/style.css" = {
      source = self + /configs/wofi-style.css;
      force = true;
    };
    ".config/alacritty/alacritty.toml".text = ''
      ${lib.optionalString (shellName == "dankshell") ''
        # DMS (enableDynamicTheming) regenerates this file live whenever the
        # system theme/wallpaper changes; Alacritty hot-reloads imports.
        [general]
        import = ["${config.home.homeDirectory}/.config/alacritty/dank-theme.toml"]
      ''}
      [font]
      size = 12

      [font.normal]
      family = "FiraCode Nerd Font"
    '';
  };
}
