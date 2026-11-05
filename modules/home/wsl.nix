{...}: {
  # Minimal headless Home Manager profile for the WSL host.
  # Terminal-only: reuses shell + git, adds a curated CLI toolchain and
  # taskwarrior sync. No desktop.nix, email, or GUI packages.
  imports = [
    ./packages-wsl.nix
    ./shell.nix
    ./git.nix
    ./secrets-wsl.nix
    ./taskwarrior.nix
    ./opencode.nix
    ./qmd.nix
    ./qmd-reindex.nix
  ];

  programs.home-manager.enable = true;

  programs.fish.shellAbbrs.rebuild = "nixos-rebuild switch --sudo --flake ~/Projects/Nix/nixos-config#wsl";

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    XDG_CONFIG_HOME = "\${HOME}/.config";
    COLORTERM = "truecolor";
  };

  home.sessionPath = [
    "\${HOME}/.local/bin"
    "\${HOME}/.cargo/bin"
  ];
}
