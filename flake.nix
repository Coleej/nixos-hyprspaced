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
  };

  outputs = {
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
                  ]
                  ++ nixpkgs.lib.optional (!isWsl) hypr-binds.homeManagerModules.x86_64-linux.default
                  ++ nixpkgs.lib.optional (!isWsl) dms.homeModules.dank-material-shell
                  ++ nixpkgs.lib.optional (!isWsl) hermes-agent.homeManagerModules.default;
                _module.args = {
                  inherit self;
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
