{
  config,
  pkgs,
  lib,
  self,
  ...
}: {
  # Taskwarrior 3 with Taskchampion sync — pure terminal, no display required.
  # Shared by every host (desktop and WSL) so the two don't drift apart.
  #
  # The encryption secret is injected into taskrc at activation from sops, so
  # it is deliberately kept out of the Home Manager-managed config below.
  programs.taskwarrior = {
    enable = true;
    package = pkgs.taskwarrior3;
    dataLocation = "${config.xdg.configHome}/task";
    # Shipped as a store path, so it is read at runtime with no extra install.
    # See configs/taskwarrior/adaptive.theme for why the stock palette is not
    # usable here: the terminal is themed dynamically (light and dark), and
    # Taskwarrior's defaults paint explicit dark backgrounds that go
    # unreadable the moment the terminal background goes light.
    #
    # Included via extraConfig rather than `colorTheme`: HM's colorTheme appends
    # a literal ".theme" to whatever it is given, which resolves to a
    # non-existent "adaptive.theme.theme" when handed a store path.
    extraConfig = ''
      include ${self + /configs/taskwarrior/adaptive.theme}
    '';
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
