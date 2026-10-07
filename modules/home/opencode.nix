{
  config,
  pkgs,
  opencodeV2,
  ...
}: {
  # opencode AI coding agent — shared by all hosts (desktop + WSL).
  # programs.opencode.enable installs the package via home.packages, so the
  # package is intentionally NOT listed in modules/shared/packages.nix or
  # modules/home/packages-wsl.nix.
  #
  # settings  → ~/.config/opencode/opencode.json  ($schema auto-added)
  # tui       → ~/.config/opencode/tui.json       (theme/keybinds live here on v1.2.15+)
  # Secrets: use opencode's "{file:<sops path>}" substitution in settings values
  # so keys stay out of the Nix store.
  #
  # `opencodeV2` is the github:Coleej/opencode-v2 flake, threaded in through
  # home-manager.users.<name>._module.args in flake.nix. Its HM module is
  # imported from that same `imports` list, because a module's own `imports` is
  # resolved before _module.args exist. The imported module sets ONLY
  # programs.opencode.package (via mkDefault) and deliberately defines no
  # settings/tui options, so it composes with the block below instead of
  # colliding with it.
  #
  # Migrating off nixpkgs' 1.x: v2 auto-migrates the SQLite data on first launch,
  # and that migration is one-way. Run scripts/opencode-v2-migrate.py by hand
  # before rebuilding on a machine that still has v1 data.
  opencode-v2 = {
    enable = true;
    package = opencodeV2.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
  };

  programs.opencode = {
    enable = true;
    settings = {
      provider = {
        hermes = {
          # Responses API (@ai-sdk/openai) instead of @ai-sdk/openai-compatible:
          # /v1/chat/completions streams a custom `hermes.tool.progress` SSE
          # event that opencode's chunk validator rejects the moment Hermes
          # calls a tool (upstream opencode#36428). /v1/responses avoids that.
          #
          # Known limitation: Hermes runs its tools server-side and still
          # surfaces them as function_call items in the /v1/responses stream,
          # so opencode logs "unavailable tool 'terminal'" and a "No user
          # message found in input" follow-up. The final answer still arrives.
          # A clean fix needs a server-side text-only patch (deferred).
          npm = "@ai-sdk/openai";
          name = "Hermes Agent";
          options = {
            baseURL = "http://100.70.193.47:8642/v1";
            # Key stays out of the Nix store: opencode reads the sops-decrypted
            # file at runtime. Declared in secrets.nix (desktop) / secrets-wsl.nix.
            apiKey = "{file:${config.sops.secrets.hermes_api_server_key.path}}";
          };
          models = {
            hermes-agent = {
              name = "Hermes Agent";
            };
          };
        };
      };
    };
    tui = {
    };
  };
}
