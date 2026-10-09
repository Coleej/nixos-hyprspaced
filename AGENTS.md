# AGENTS.md — NixOS Hyprspace Configuration

## Overview

Flake-based NixOS configuration with Hyprland (Wayland compositor), Home Manager, and sops-nix
secrets. Three hosts are defined in `flake.nix`'s `hosts` attrset: `thinkpad` and `amd-workstation`
(Hyprland desktops) and `wsl` (headless NixOS-WSL, terminal-only) — more can be added the same way.

The desktop shell is switchable via the `hyprspace.shell` enum (`"waybar"` | `"dankshell"`), set in
`modules/shared/default.nix`. DankMaterialShell (DMS) replaces waybar, wofi, dunst, hyprpaper,
hyprlock, and hypridle. See the **Desktop shell switch** section below.

`makeHostConfig` supports two optional per-host flags in the `hosts` attrset: `wsl = true` adds
`nixos-wsl.nixosModules.default` and omits the `hypr-binds` and `dms` HM modules; `homeModule`
selects the Home Manager entrypoint (default `./home.nix`; WSL uses `./home-wsl.nix`).

**Repo structure:**
```
hyprspace/
├── flake.nix                  # Flake inputs (nixpkgs, home-manager, hyprland, hypr-binds, sops-nix, dms) + hosts attrset
├── hosts/
│   ├── thinkpad/
│   │   ├── system.nix          # Host NixOS config (imports modules/shared)
│   │   ├── hardware-configuration.nix
│   │   └── monitors.lua        # Per-host monitor layout
│   ├── amd-workstation/
│   │   ├── system.nix          # Same as thinkpad, plus hyprspace.hyprland.amd.enable + hyprspace.gaming.enable
│   │   ├── hardware-configuration.nix
│   │   └── monitors.lua
│   └── wsl/
│       └── system.nix          # Headless NixOS-WSL host (no hardware-configuration.nix, no bootloader/kernel)
├── modules/
│   ├── shared/                # NixOS modules, options under hyprspace.<name>
│   │   ├── default.nix         # hyprspace.enable gate + hyprspace.shell switch + default sub-option wiring
│   │   ├── user.nix            # User creation (hyprspace.user.*)
│   │   ├── desktop.nix         # greetd+tuigreet, portals, fonts, Wayland session vars, greeter user
│   │   ├── hyprland.nix        # Hyprland + hyprpaper/hyprlock/hypridle systemd services (off when dankshell)
│   │   ├── waybar.nix          # Waybar systemd service + config install
│   │   ├── dankshell.nix       # DankMaterialShell system integration (accounts-daemon, geoclue2, upower)
│   │   ├── services.nix        # openssh, tlp, pam keyring
│   │   ├── system.nix          # Kernel, zram, fstrim, Nix GC, power management
│   │   ├── packages.nix        # base/desktop/dev package groups
│   │   ├── gaming.nix          # Steam, Gamescope, gamemode (amd-workstation only)
│   │   └── android.nix         # Android Studio / SDK
│   └── home/                  # Home Manager modules, plain HM options (no hyprspace.* namespace)
│       ├── default.nix         # Desktop HM entrypoint (imports below) + session vars/path
│       ├── packages.nix        # home.packages (CLI + GUI apps: firefox, obsidian, etc.)
│       ├── shell.nix           # Fish + Starship prompt + fzf + direnv (shared by desktop + WSL)
│       ├── desktop.nix         # GTK theme, alacritty, wofi (gated by shell), hypr-binds, writes shell.lua, installs configs/* via home.file
│       ├── dankshell.nix       # programs.dank-material-shell (gated by osConfig hyprspace.dankshell.enable)
│       ├── services.nix        # netrc activation script, gnome-keyring + nextcloud user services
│       ├── secrets.nix         # sops age key + secret declarations (desktop)
│       ├── git.nix, email.nix  # git config (shared), Proton Mail Bridge
│       ├── opencode.nix        # programs.opencode (shared) — package + opencode.json/tui.json on all hosts; hermes provider apiKey via sops {file:...}
│       ├── wsl.nix             # Headless WSL HM entrypoint — imports packages-wsl/shell/git/secrets-wsl/taskwarrior/opencode
│       ├── packages-wsl.nix    # Curated headless CLI/dev packages (no GUI)
│       ├── secrets-wsl.nix     # sops wiring for WSL — taskchampion_secret, anthropic_api_key_wsl, hermes_api_server_key
│       └── taskwarrior.nix     # Taskwarrior 3 + taskchampion sync (shared by desktop + WSL; secret injected at activation, palette via configs/taskwarrior/adaptive.theme)
│       # wsl skips qmd-mcp.nix (no GPU passthrough) — its Claude Code qmd MCP server
│       # runs natively on the Windows host instead, via Task Scheduler (outside Nix).
│       # Those Windows tasks launch via a wscript.exe .vbs wrapper (WshShell.Run with
│       # windowStyle=0), not `powershell.exe -WindowStyle Hidden`: PowerShell/node.exe
│       # are console-subsystem binaries that flash a window before hiding it — only
│       # wscript.exe suppresses the window at process-creation time. Scripts live in
│       # %LOCALAPPDATA%\qmd\ on the Windows host.
├── configs/                   # Dotfiles installed by modules/home/desktop.nix or the hyprspace-setup service
│   ├── hyprland.lua            # Base Hyprland config (hl.* Lua API); branches on shell via shell.lua
│   ├── autostart.lua           # exec-once; waybar-only bits gated on shell
│   ├── keybinds.lua            # Keybindings; shell-specific launcher/lock/media keys
│   ├── window-rules.lua
│   ├── animations.lua
│   ├── hyprpaper-default.conf  # Template, __WALLPAPER__ substituted at activation (waybar stack)
│   ├── hyprlock-default.conf   # Template, __WALLPAPER__ substituted at activation (waybar stack)
│   ├── hypridle-default.conf   # waybar stack
│   ├── wofi-style.css
│   ├── taskwarrior/
│   │   └── adaptive.theme      # Background-free colour theme (readable on light + dark terminals), included by modules/home/taskwarrior.nix
│   └── waybar/
│       ├── config.json         # thinkpad (has battery)
│       ├── config-amd-workstation.json  # (no battery module — see hosts/*/system.nix comment)
│       └── base.css, cyberpunk.css, catppuccin-*.css  # Theme variants; active theme selected via
│                                                        # hyprspace.waybar.stylePath in each host's
│                                                        # system.nix (currently cyberpunk.css)
├── scripts/
│   ├── hyprland/               # brightness.sh, show-keybindings.sh
│   ├── waybar/                 # waybar-dunst.sh, waybar-mpris.sh, waybar-public-ip.sh
│   └── rofi-brightness.sh
├── secrets/secrets.yaml       # sops-encrypted secrets (edit with `sops secrets/secrets.yaml`)
├── .sops.yaml                 # age recipient key used to encrypt secrets/secrets.yaml
├── wallpapers/default.jpg     # Placeholder — replace with your wallpaper
├── .githooks/pre-commit       # Auto-formats staged .nix files with alejandra
├── home.nix                   # Desktop HM entrypoint → modules/home/default.nix (username/homeDirectory/stateVersion)
├── home-wsl.nix               # WSL HM entrypoint → modules/home/wsl.nix
└── flake.lock
```

## Build / Eval Commands

### Evaluate the full configuration
```bash
# System config
nix eval .#nixosConfigurations.thinkpad.config.system.build.toplevel --json

# Home Manager user config
nix eval .#nixosConfigurations.thinkpad.config.home-manager.users.cody --json
```

### Build and apply
```bash
# Dry-run / type-check
sudo nixos-rebuild dry-activate --flake .#thinkpad        # or .#amd-workstation

# Apply (system + Home Manager - use this!)
sudo nixos-rebuild switch --flake .#thinkpad

# Build only (no switch)
nixos-rebuild build --flake .#thinkpad

# Home Manager only (faster iteration, no system rebuild)
home-manager switch --flake .#thinkpad
```

### Formatting / Linting
```bash
# Format all .nix files (alejandra — idempotent, no-conflict formatting)
nix run nixpkgs#alejandra -- .

# Lint with statix (static analysis for Nix)
nix run nixpkgs#statix -- fix --mode=clippy ./modules/shared/*.nix

# Check formatting
nix run nixpkgs#alejandra -- --check .
```

### Single-file eval (useful for debugging a specific Nix expression)
```bash
nix eval --file ./modules/shared/hyprland.nix --apply 'x: x.options.hyprspace.hyprland' 2>/dev/null
```

## Code Style Guidelines

### General Conventions
- **Flakes-first**: Always use flakes. No `niv` or channel-based approaches.
- **Modular structure**: System config in `hosts/<name>/system.nix`, reusable NixOS logic in
  `modules/shared/` (under the `hyprspace.*` option namespace), reusable Home Manager logic in
  `modules/home/` (plain HM options, imported via `home.nix`), shared dotfile configs in `configs/`.
- **Multi-host**: Host-specific data (username, groups, hostname, monitor config) lives in
  `flake.nix` (`hosts` attr) and `hosts/<name>/system.nix` + `hosts/<name>/monitors.lua`.
  Shared modules have no host-specific values baked in.
- **State version**: Always set `stateVersion` to the NixOS release actually in use (currently `"25.11"` for both `system.stateVersion` and `home.stateVersion`); don't bump casually.

### Nix Language Style
- **Formatter**: `alejandra` (idempotent). Run before committing.
- **Indentation**: 2 spaces.
- **Attribute ordering**: Alphabetical within attribute sets, or logical (imports first).
- **Imports**: Single `imports = []` at top of each module.
- **Package references**: Always `pkgs.<name>`. Avoid `with pkgs;` at top level.
- **Quotes**: Double quotes for strings; single quotes only where needed.
- **Error handling**: No `|| true` or silent failures. Nix is declarative — fail loudly.

### Naming Conventions
- **Module prefix**: `hyprspace.<submodule>` for NixOS modules only (e.g., `hyprspace.hyprland`,
  `hyprspace.waybar`, `hyprspace.gaming`). Home Manager modules under `modules/home/` use plain
  `programs.*`/`home.*`/`services.*` — no namespace indirection.
- **Option names**: `lowerCamelCase` (matches NixOS convention).
- **File names**: `kebab-case.nix` for modules.
- **Host names**: `thinkpad`, `amd-workstation`, `wsl`. Add more the same way in `flake.nix`.

### Nixpkgs Usage
- **Package sets**: Always `pkgs.<name>`. No bare package names.
- **Unfree packages**: Set `nixpkgs.config.allowUnfree = true` only in `hosts/<name>/system.nix`.
- **Overlays**: Define in `flake.nix` if you need custom packages.

### Module System
- **Module args**: Prefer `{ config, pkgs, lib, ... }` as the function signature.
- **Enable toggles**: Every `modules/shared/` submodule has a `hyprspace.<name>.enable` option.
- **User info**: Shared via `hyprspace.user.<field>` options (defined in `modules/shared/user.nix`).
  Host-specific values set in `flake.nix` (hosts attr) and passed to `hosts/<name>/system.nix`.

### Home Manager
- **User packages**: Add to `home.packages` in `modules/home/packages.nix`, not `environment.systemPackages`.
- **Shell integration**: Fish config lives in `modules/home/shell.nix` (`programs.fish.interactiveShellInit`); prompt via `programs.starship`, fuzzy search via `programs.fzf`.
- **Secrets**: Never hardcode secrets. Declare them in `modules/home/secrets.nix` and encrypt values
  in `secrets/secrets.yaml` with `sops` (age key at `~/.config/sops/age/keys.txt`); reference the
  decrypted path via `config.sops.secrets.<name>.path`.

## Desktop shell switch

The desktop shell stack is selected by **`hyprspace.shell`** (`"waybar"` | `"dankshell"`, default
`"waybar"`), currently set to `"dankshell"` in `modules/shared/default.nix`. One line flips both
desktops; a host can override with `lib.mkForce`.

- **NixOS side**: `modules/shared/default.nix` derives `hyprspace.waybar.enable` /
  `hyprspace.dankshell.enable` from the enum (both `lib.mkDefault`). `modules/shared/dankshell.nix`
  wires system integration (accounts-daemon, geoclue2, upower — all `mkDefault`). The
  hyprpaper/hypridle/hyprlock systemd user services in `modules/shared/hyprland.nix` are gated off
  when dankshell is active.
- **HM side**: `modules/home/dankshell.nix` enables `programs.dank-material-shell` (dms flake HM
  module, imported in `flake.nix` for non-WSL hosts) when `osConfig.hyprspace.dankshell.enable`.
  DMS settings/session are deliberately unmanaged — tweak in the GUI; codify into
  `programs.dank-material-shell.settings` later if desired.
- **Lua side**: `modules/home/desktop.nix` writes `~/.config/hypr/shell.lua` (just
  `return "<shell>"`). `keybinds.lua`, `autostart.lua`, and `hyprland.lua` branch on it
  (launcher/lock/media keys, dunst/hypridle/tray applets, DMS layer rule + `dms.*` requires).
  The dms.* requires are `pcall`-guarded because DMS generates them after first login.
- **Waybar stack preservation**: hosts keep their `hyprspace.waybar` configPath/stylePath/scriptsDir
  values without `enable = true`, so flipping back to `"waybar"` restores the full old stack.

The DMS flake input is `github:AvengeMedia/DankMaterialShell/stable`. first build compiles the
`dms` Go CLI from source (a few minutes). `dgop` (system monitoring) comes from nixpkgs;
quickshell 0.3.1+ from nixpkgs is used.

## Adding a New Host

1. Add entry to `flake.nix` `hosts` attr:
   ```nix
   workstation = {
     user = {
       name = "alice";
       group = "users";
       home = "/home/alice";
       description = "Alice";
       extraGroups = [ "libvirtd" ];
     };
   };
   ```

2. Create directory and copy hardware config:
   ```bash
   mkdir -p hosts/workstation
   cp hosts/thinkpad/hardware-configuration.nix hosts/workstation/
   cp hosts/thinkpad/monitors.lua hosts/workstation/
   ```

3. Edit `hosts/workstation/system.nix` (copy from `hosts/thinkpad/system.nix` as a starting point):
   - `hyprspace.hyprland.monitorsFile` should point at `./monitors.lua`
   - Update `networking.hostName`

4. Edit `hosts/workstation/monitors.lua` with your monitor setup.

5. Add the new host to the `monitorsFile` attrset in `modules/home/desktop.nix` (keyed by
   `hostName`) — it throws if a host isn't listed there.

6. Rebuild: `sudo nixos-rebuild switch --flake .#workstation`

## Known Issues

### NVIDIA Legacy GPU Support (e.g., ThinkPad GeForce 920M)

The NVIDIA 5xx+ proprietary drivers dropped support for Maxwell (GM10x) GPUs. If a host has an
older NVIDIA dGPU (e.g., GeForce 920M), the default `nixpkgs` driver will fail to initialize —
causing kernel panics or post-boot lockups. Symptoms include `[drm] No compatible format found`
and `Cannot find any crtc or sizes` in dmesg.

**Fix options in `hosts/<name>/system.nix`:**

1. **Drop NVIDIA entirely** (recommended for weak dGPUs on Wayland):
   ```nix
   services.xserver.videoDrivers = ["modesetting"];
   # remove all hardware.nvidia.* blocks
   ```

2. **Pin legacy driver** (if you need NVIDIA):
   ```nix
   services.xserver.videoDrivers = ["nvidia"];
   hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.legacy_470;
   ```

For per-host Hyprland GPU selection, add `env` to the host-specific Lua config
(e.g., `hosts/<name>/monitors.lua` or a host-local lua file required from `hyprland.lua`):
```lua
hl.env("WLR_DRM_DEVICES", "/dev/dri/card0")
```
Don't put GPU-specific `env` in the shared `configs/hyprland.lua`.

## Current Status

greetd+tuigreet is the display manager for all graphical hosts (thinkpad, amd-workstation). The
`dankshell` branch implements the DankMaterialShell stack behind `hyprspace.shell` (see **Desktop
shell switch**); master stays on the waybar stack until merged.

### Next Steps
- Implement DankMaterialShell (see **Desktop shell switch**)
- Update flake to latest inputs

## Workflow Tips

- **Pre-commit hook**: Installed via `.githooks/pre-commit`. Run `git config core.hooksPath .githooks` on new clones to enable it. Auto-formats staged `.nix` files with alejandra before each commit.
- **Debugging**: Use `nix eval .#nixosConfigurations.thinkpad.config.hyprspace.hyprland.enable`
- **flake.lock**: Commit it for reproducible builds. Update with `nix flake update`
- **Secrets**: Edit `secrets/secrets.yaml` with `sops secrets/secrets.yaml` — never hand-edit the
  encrypted file directly.
- **Display manager**: greetd+tuigreet is configured in `modules/shared/desktop.nix`
  (`services.greetd`). To switch DMs, edit that file; auto-login and tuigreet flags live in the
  same block. The `greeter` user is created in the same module and is intentionally separate from
  `hyprspace.user`.
