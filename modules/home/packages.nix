{pkgs, ...}: let
  qmlls = pkgs.runCommand "qmlls" {} ''
    mkdir -p $out/bin
    ln -s ${pkgs.qt6.qtdeclarative}/bin/qmlls $out/bin/qmlls
  '';

  # Firefox with a locked pref so Firefox Sync can never change the active
  # theme. Sync syncs extensions.activeThemeID and, on an incoming value,
  # enables that built-in theme (services-sync/engines/prefs.sys.mjs
  # _maybeEnableBuiltinTheme); another device on the account used a dark
  # built-in theme, which pinned this machine dark regardless of the desktop
  # colour scheme (docs/dev/dms-theme-sync.md). A user.js false is not
  # enough -- an incoming null control pref clears it mid-sync -- so it must
  # be locked via the wrapper's autoconfig (mozilla.cfg).
  firefox-locked = pkgs.firefox.override {
    extraPrefs = ''
      lockPref("services.sync.prefs.sync.extensions.activeThemeID", false);
    '';
  };
in {
  home.packages = with pkgs; [
    neovim
    git
    ripgrep
    fd
    fzf
    eza
    bat
    jq
    wget
    curl
    tree
    htop
    btop
    fastfetch
    direnv
    gh
    cups-pk-helper
    uv
    newsboat
    git-lfs
    ranger
    xclip
    firefox-locked
    tree-sitter
    telegram-desktop
    whosthere
    dig
    remmina
    pyright
    lua-language-server
    qmlls
    ruff
    stylua
    nixd
    nixfmt
    taskwarrior3
    tre-command
    imagemagick
    protonmail-bridge-gui
    obsidian
    sparrow
  ];
}
