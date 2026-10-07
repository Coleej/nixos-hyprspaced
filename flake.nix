{
  description = "NixOS system configuration with Hyprland";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland.url = "github:hyprwm/Hyprland";
    hyprland.inputs.nixpkgs.follows = "nixpkgs";
    hypr-binds = {
      url = "github:hyprland-community/hypr-binds";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-code-nix = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    qmd = {
      url = "github:tobi/qmd";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dms = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # NOTE: do not `follows` nixpkgs here. hermes-agent's desktop.nix pins an
    # `electronHeaders` sha256 against the electron version of its own locked
    # nixpkgs; following ours drifts the electron version and breaks the hash.
    hermes-agent.url = "github:NousResearch/hermes-agent";
    # opencode v2, packaged from official prebuilt binaries by
    # github:Coleej/opencode-v2. Also deliberately not following nixpkgs: the
    # flake pins its own, and modules/home/opencode.nix uses its
    # `packages.<system>.opencode` output, which is built with that pin.
    #
    # The rev is pinned in the URL because the repo has no tags yet. Drop the
    # `?rev=` once a release is tagged. Bumps arrive as PRs from the flake's own
    # update workflow, which is the intended point to move this forward and
    # re-run scripts/opencode-v2-migrate.py.
    opencode-v2 = {
      url = "git+ssh://git@github.com/Coleej/opencode-v2.git?rev=243a792383f829af861981023795da6b7c9649a0";
    };
  };

  # `inputs@` binds the whole input set alongside the individual names, so
  # inputs that are not valid Nix identifiers (opencode-v2) can still be passed
  # down. Do NOT reach for `self.inputs` inside a module instead: self refers to
  # these very outputs, so it re-enters evaluation and nix reports infinite
  # recursion.
  outputs = inputs @ {
    self,
    nixpkgs,
    home-manager,
    hyprland,
    hypr-binds,
    sops-nix,
    nixos-wsl,
    claude-code-nix,
    qmd,
    dms,
    hermes-agent,
    ...
  }: let
    hosts = {
      thinkpad = {
        user = {
          name = "cody";
          group = "users";
          home = "/home/cody";
          description = "Cody";
          extraGroups = [];
        };
      };
      amd-workstation = {
        user = {
          name = "cody";
          group = "users";
          home = "/home/cody";
          description = "Cody";
          extraGroups = [];
        };
      };
      x1 = {
        user = {
          name = "cody";
          group = "users";
          home = "/home/cody";
          description = "Cody";
          extraGroups = [];
        };
      };
      wsl = {
        wsl = true;
        homeModule = ./home-wsl.nix;
        user = {
          name = "cody";
          group = "users";
          home = "/home/cody";
          description = "Cody";
          extraGroups = [];
        };
      };
    };

    makeHostConfig = hostName: hostData: let
      isWsl = hostData.wsl or false;
    in
      nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules =
          [
            ./hosts/${hostName}/system.nix
            home-manager.nixosModules.home-manager
            sops-nix.nixosModules.sops
          ]
          ++ nixpkgs.lib.optional isWsl nixos-wsl.nixosModules.default
          ++ [
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${hostData.user.name} = {
                imports =
                  [
                    (hostData.homeModule or ./home.nix)
                    sops-nix.homeManagerModules.default
                    qmd.homeModules.default
                    # opencode v2's HM module. Imported HERE rather than from
                    # modules/home/opencode.nix because a module's own `imports`
                    # list is resolved during module collection, before
                    # extraSpecialArgs or _module.args exist -- referencing
                    # either from `imports` makes nixpkgs' module system report
                    # "infinite recursion". Resolving it here, in flake scope,
                    # is the supported way to thread a flake into HM.
                    inputs.opencode-v2.homeManagerModules.opencode-v2
                  ]
                  ++ nixpkgs.lib.optional (!isWsl) hypr-binds.homeManagerModules.x86_64-linux.default
                  ++ nixpkgs.lib.optional (!isWsl) dms.homeModules.dank-material-shell
                  ++ nixpkgs.lib.optional (!isWsl) hermes-agent.homeManagerModules.default;
                # Bound as `opencodeV2`, not `opencode-v2`: a module argument of
                # that name would shadow the `opencode-v2.*` option namespace the
                # imported module defines, so `opencode-v2.enable` would resolve
                # against the flake instead of the option. _module.args (not
                # extraSpecialArgs) because that is what the existing HM modules
                # here already consume.
                _module.args = {
                  inherit self;
                  opencodeV2 = inputs.opencode-v2;
                  hostName = hostName;
                  hostUser = hostData.user;
                  claudeCodePackage = claude-code-nix.packages.x86_64-linux.claude-code;
                };
              };
            }
            {_module.args = {inherit hyprland self;};}
          ];
        specialArgs = {
          inherit hyprland self;
          hostUser = hostData.user;
        };
      };
  in {
    formatter.x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.alejandra;

    nixosModules = {
      hyprspace = import ./modules/shared;
    };

    nixosConfigurations = nixpkgs.lib.mapAttrs makeHostConfig hosts;
  };
}
