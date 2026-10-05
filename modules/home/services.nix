{
  config,
  pkgs,
  lib,
  ...
}: {
  programs.taskwarrior = {
    enable = true;
    package = pkgs.taskwarrior3;
    dataLocation = "${config.xdg.configHome}/task";
    config = {
      rc.taskrc = "${config.xdg.configHome}/task/taskrc";
      sync.server.url = "https://taskchampion.codyjohnson.xyz";
      sync.server.client_id = "9ddb3dd1-e22e-469c-99c0-9a054fecb6bd";
    };
  };

  home.activation.writeNetrc = lib.hm.dag.entryAfter ["linkGeneration"] ''
    secret_path="${config.sops.secrets.nextcloud_password.path}"
    if [ -f "$secret_path" ]; then
      password=$(cat "$secret_path")
      printf 'machine nc.codyjohnson.xyz\nlogin cody\npassword %s\n' "$password" > "$HOME/.netrc"
      chmod 600 "$HOME/.netrc"
    fi
  '';

  home.activation.writeTaskchampionSecret = lib.hm.dag.entryAfter ["linkGeneration"] ''
    secret_path="${config.sops.secrets.taskchampion_secret.path}"
    taskrc="${config.xdg.configHome}/task/taskrc"
    if [ -f "$secret_path" ]; then
      secret=$(cat "$secret_path")
      mkdir -p "${config.xdg.configHome}/task"
      if [ -f "$taskrc" ]; then
        ${pkgs.gnused}/bin/sed -i '/^sync\.encryption_secret=/d' "$taskrc"
      fi
      echo "sync.encryption_secret=$secret" >> "$taskrc"
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
