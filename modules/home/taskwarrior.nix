{
  config,
  pkgs,
  lib,
  ...
}: {
  # Taskwarrior 3 with Taskchampion sync — pure terminal, no display required.
  # The encryption secret is injected into taskrc at activation from sops.
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
}
