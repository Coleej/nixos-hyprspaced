{pkgs, ...}: {
  # NixOS-WSL host. The nixos-wsl module (added in flake.nix) supplies the
  # kernel, bootloader, and root filesystem — so there is deliberately no
  # hardware-configuration.nix, no boot loader, and no boot.kernelPackages here.
  # This host does not import modules/shared's desktop stack (hyprland/waybar/
  # desktop/gaming); it is headless and terminal-only. It does import
  # packages.nix directly for the shared dev toolchain (gnumake, cmake, etc.).
  imports = [../../modules/shared/packages.nix];

  hyprspace.packages = {
    enable = true;
    base.enable = true;
    dev.enable = true;
    rust.enable = true;
  };

  wsl.enable = true;
  wsl.defaultUser = "cody";
  # Previously true: older WSL never registered the WSLInterop binfmt_misc
  # handler on this host, so .exe files (e.g. surge_stat.exe) couldn't run.
  # WSL 3.0 locks /proc/sys/fs/binfmt_misc/status read-only, which makes
  # systemd-binfmt exit 1 on every boot/switch (its flush hits EROFS). Testing
  # whether WSL 3.0 now registers WSLInterop itself; if .exe files stop
  # working after `wsl.exe --shutdown`, set this back to true.
  wsl.interop.register = false;

  networking.hostName = "wsl";

  services.tailscale.enable = true;

  # cody is created by wsl.defaultUser; just set the login shell and grant sudo.
  users.users.cody = {
    shell = pkgs.fish;
    extraGroups = [
      "wheel"
      "docker"
    ];
  };
  programs.fish.enable = true;

  virtualisation.docker.enable = true;

  environment.systemPackages = with pkgs; [
    gcc

    azure-cli

    # nbconvert's LaTeX exporter shells out to pandoc for markdown -> LaTeX
    # cell conversion (not just the xelatex backend below).
    pandoc

    # TeX Live for `jupyter nbconvert --to pdf` (xelatex backend). nbconvert's
    # own docs suggest texlive-xetex + texlive-fonts-recommended +
    # texlive-plain-generic (Debian package names), but its default LaTeX
    # template (style_jupyter.tex.j2 / base.tex.j2) also needs several
    # packages not in that set -- found by iterating actual xelatex "File
    # X.sty not found" errors on a real notebook export (2026-07-28):
    # tcolorbox (+ pgf/environ/trimspaces/pdfcol), upquote, titling,
    # enumitem, ulem, soul, rsfs (mathrsfs.sty), adjustbox (+ collectbox),
    # eurosym, grffile, fancyvrb. scheme-medium already covers the rest
    # (graphicx, caption, float, xcolor, geometry, amsmath, hyperref, ...).
    # Not texlive.combined.scheme-full, which is multiple GB.
    (texliveMedium.withPackages (
      ps:
        with ps; [
          tcolorbox
          pgf
          environ
          trimspaces
          pdfcol
          upquote
          titling
          enumitem
          ulem
          soul
          rsfs
          adjustbox
          collectbox
          eurosym
          grffile
          fancyvrb
        ]
    ))
  ];

  # Lets uv's own downloaded Python builds (and other prebuilt, dynamically
  # linked binaries for generic Linux) execute at all -- NixOS has no
  # standard dynamic-linker path by default and blocks them with a
  # "stub-ld" error otherwise. Kept deliberately limited to uv/Python
  # development needs; add more libraries here as specific tools need them.
  programs.nix-ld = {
    enable = true;
    libraries = [
      pkgs.zlib
      pkgs.stdenv.cc.cc.lib
      pkgs.expat
    ];
  };

  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "America/Chicago";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;

  system.stateVersion = "26.05";
}
