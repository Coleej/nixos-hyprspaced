{
  config,
  pkgs,
  lib,
  ...
}: {
  # taskwarrior itself lives in ./taskwarrior.nix so desktop and WSL share one
  # definition; it is imported from ./default.nix.

  home.activation.writeNetrc = lib.hm.dag.entryAfter ["linkGeneration"] ''
    secret_path="${config.sops.secrets.nextcloud_password.path}"
    if [ -f "$secret_path" ]; then
      password=$(cat "$secret_path")
      printf 'machine nc.codyjohnson.xyz\nlogin cody\npassword %s\n' "$password" > "$HOME/.netrc"
      chmod 600 "$HOME/.netrc"
    fi
  '';

  systemd.user.targets.graphical-session = {
    Unit = {
      RefuseManualStart = lib.mkForce false;
    };
  };

  systemd.user.services.gnome-keyring-daemon = {
    Unit = {
      Description = "GNOME Keyring daemon";
      Before = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --start --foreground --components=secrets";
      Restart = "on-failure";
    };
    Install.WantedBy = ["graphical-session.target"];
  };

  systemd.user.services.nextcloud-sync = {
    Unit = {
      Description = "Nextcloud sync";
      After = "network-online.target";
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.nextcloud-client}/bin/nextcloudcmd -n %h/Nextcloud https://nc.codyjohnson.xyz/";
    };
    Install.WantedBy = ["multi-user.target"];
  };

  systemd.user.timers.nextcloud-sync = {
    Unit.Description = "Auto-sync Nextcloud files hourly";
    Timer = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";
    };
    Install.WantedBy = ["timers.target"];
  };
}
