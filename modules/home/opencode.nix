{
  config,
  pkgs,
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
  programs.opencode = {
    enable = true;
    # nixpkgs unstable ships opencode v2. The override pins the node_modules
    # FOD hash: nixos-unstable's 2.2.5 carries a stale hash, already fixed on
    # nixpkgs master with the per-platform outputHash below (this value is
    # master's Linux hash). Drop the override once nixos-unstable advances
    # past that fix.
    package = pkgs.opencode.overrideAttrs (old: {
      node_modules = old.node_modules.overrideAttrs (_: {
        outputHash = "sha256-prx9dX7kUvs/E3zopkaPk5LXh3xJAy5sZeum/W8L7cA=";
      });
    });
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
