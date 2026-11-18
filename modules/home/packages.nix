{pkgs, ...}: let
  qmlls = pkgs.runCommand "qmlls" {} ''
    mkdir -p $out/bin
    ln -s ${pkgs.qt6.qtdeclarative}/bin/qmlls $out/bin/qmlls
  '';

  # TeamViewer ships only the xcb platform plugin, but
  # modules/shared/desktop.nix exports QT_QPA_PLATFORM=wayland session-wide, so
  # Qt looks for a "wayland" plugin, finds none and aborts during
  # QGuiApplication init ("no Qt platform plugin could be initialized" -- a
  # SIGABRT core dump with no visible error, since the GUI is spawned as a
  # detached child). Force the X11 plugin (runs through XWayland) for this app
  # only, leaving other Qt apps on Wayland.
  #
  # symlinkJoin rather than a bare writeShellScriptBin: the package's share/
  # tree is what puts TeamViewer in the launcher, and that .desktop file's
  # Exec= points straight at the unwrapped launcher inside the store (so it
  # never goes through bin/teamviewer). Keep the tree, swap the binary, and
  # repoint Exec= at the wrapper.
  teamviewer-x11 = pkgs.symlinkJoin {
    name = "teamviewer-x11";
    paths = [pkgs.teamviewer];
    postBuild = ''
      rm $out/bin/teamviewer
      cat > $out/bin/teamviewer <<'EOF'
      #!${pkgs.runtimeShell}
      export QT_QPA_PLATFORM=xcb
      exec ${pkgs.teamviewer}/bin/teamviewer "$@"
      EOF
      chmod +x $out/bin/teamviewer
      # buildEnv links the .desktop in as a store symlink; substitute needs a
      # real file to write, so replace the link with a patched copy.
      rm $out/share/applications/com.teamviewer.TeamViewer.desktop
      substitute ${pkgs.teamviewer}/share/applications/com.teamviewer.TeamViewer.desktop \
        $out/share/applications/com.teamviewer.TeamViewer.desktop \
        --replace-fail \
        'Exec=${pkgs.teamviewer}/share/teamviewer/tv_bin/script/teamviewer' \
        "Exec=$out/bin/teamviewer"
    '';
  };

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
      // Leftovers from earlier experiments still sit in prefs.js (removing a
      // pref from user.js does not unset it); clearPref returns them to
      // defaults at every start. The two widget./systemTheme prefs do not
      // exist in Firefox 158 at all.
      clearPref("widget.systemUsesDarkTheme");
      clearPref("extensions.systemTheme.update.enabled");
      clearPref("toolkit.startup.max_resumed_crashes");
      clearPref("browser.sessionstore.resume_from_crash");
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
    freerdp # xfreerdp CLI — quick RDP testing/debugging alongside the Remmina GUI
    teamviewer-x11 # wrapper forcing X11 (see let block above)
    pyright
    lua-language-server
    qmlls
    ruff
    stylua
    nixd
    nixfmt
    tre-command
    imagemagick
    protonmail-bridge-gui
    obsidian
    sparrow
  ];
}
