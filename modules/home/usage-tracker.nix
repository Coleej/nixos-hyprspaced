{
  config,
  pkgs,
  lib,
  ...
}: let
  # AI usage tracker: one enum selects the backend (a CLI in home.packages plus
  # a DMS widget under programs.dank-material-shell.plugins). Change
  # programs.usageTracker.backend to "none" to disable, or add another backend
  # to the `backends` attrset below and flip the enum to swap.
  #
  # Each backend's plugin attr name must equal the plugin manifest's `id` (not
  # the directory name), so settings the GUI writes to plugin_settings.json key
  # correctly. Unselected backends are never fetched or built.
  #
  # opentracker CLI — Go, MIT, tagged releases, modular providers (OpenCode Go /
  # Zen / Codex / Claude). Build + hashes verified in docs/dev/opentracker.md.
  opentracker = pkgs.buildGoModule rec {
    pname = "opentracker";
    version = "1.5.1";
    src = pkgs.fetchFromGitHub {
      owner = "wsmajt";
      repo = "opentracker";
      rev = "v${version}";
      hash = "sha256-uhEY8V0utfMOFZbU/hW9rSw/LIGFOEUiE5OgsVz1lL4=";
    };
    vendorHash = "sha256-h2KZAB3pYdJAPotdj7YxF9P39EEk5OyCef2Esq2SWBA=";
    ldflags = ["-s" "-w" "-X" "main.version=${version}"];
  };

  # One entry per backend. `packages` -> home.packages; `plugins` ->
  # programs.dank-material-shell.plugins (declared with only `src`, so
  # plugin_settings.json stays unmanaged and the enabled flag remains a GUI
  # step, matching the existing convention).
  backends = {
    opentracker = {
      # OpenCode Go needs only the opentracker CLI itself — no codex package.
      # Re-add pkgs.codex here if you ever want the OpenAI Codex provider.
      packages = [opentracker];
      plugins = {
        openTrackerBar = {
          src = pkgs.fetchFromGitHub {
            owner = "wsmajt";
            repo = "OpenTrackerBar";
            rev = "a2fcb5c0e788185ac2d2828e4ed42de78c87073d";
            hash = "sha256-2yI30jIWn2fdiTU8LkQO2AzbJEBXn/iF8x4vOmuAE+E=";
          };
        };
      };
    };
  };
in {
  options.programs.usageTracker = {
    backend = lib.mkOption {
      type = lib.types.enum (lib.attrNames backends ++ ["none"]);
      default = "opentracker";
      description = ''
        AI usage tracker backend to install: a CLI in home.packages plus a DMS
        widget in programs.dank-material-shell.plugins. "none" installs neither.
      '';
    };
  };

  config = let
    selected = backends.${config.programs.usageTracker.backend} or {};
  in
    lib.mkIf (config.programs.usageTracker.backend != "none") {
      home.packages = selected.packages or [];
      programs.dank-material-shell.plugins = selected.plugins or {};
    };
}
