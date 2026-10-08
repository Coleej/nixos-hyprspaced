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

  # github.com maps to the work key in ~/.ssh/config here, but private flake
  # inputs (opencode-v2) need the personal key. --sudo keeps the fetch as cody
  # so GIT_SSH_COMMAND and ~/.ssh apply.
  programs.fish.shellAbbrs.rebuild = "env GIT_SSH_COMMAND=\"ssh -i $HOME/.ssh/id_ed25519 -o IdentitiesOnly=yes\" nixos-rebuild switch --sudo --flake ~/Projects/Nix/nixos-config#wsl";

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
