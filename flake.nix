{
    description = "OpenPICL Flakes Development Environment.";

    inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

        rust-overlay = {
            url = "github:oxalica/rust-overlay";
            inputs.nixpkgs.follows = "nixpkgs";
        };

        flake-utils.url = "github:numtide/flake-utils";
    };

    outputs = { self, nixpkgs, rust-overlay, flake-utils, ... }:
        flake-utils.lib.eachDefaultSystem (system:
            let
                pkgs = import nixpkgs {
                    inherit system;
                    config = {
                        allowUnfree = true;

                        substituters = [
                            "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
                            "https://mirrors.ustc.edu.cn/nix-channels/store"
                            "https://mirror.sjtu.edu.cn/nix-channels/store"
                        ];
                    };
                    overlays = [ rust-overlay.overlays.default ];
                };

                rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

                nodejs = pkgs.nodejs_24;

                wasm-bindgen-cli = pkgs.wasm-bindgen-cli.overrideAttrs (old: {
                    version = "0.2.126";
                    src = pkgs.fetchCrate {
                    crateName = "wasm-bindgen-cli";
                    version = "0.2.126";
                    sha256 = "sha256-H6Is3fiZVxZCfOMWK5dWMSrtn50VGv0sfdnsT+cTtyk=";
                };
                cargoSha256 = "";
            });
            in
            {
                devShells.default = pkgs.mkShell {
                    buildInputs = with pkgs; [
                        # Rust Toolchain
                        rustToolchain

                        # Leptos
                        cargo-leptos
                        wasm-bindgen-cli

                        # Node.js runtime
                        nodejs

                        # Just
                        just

                        # system tools
                        lld
                        clang
                    ];

                    shellHook = ''
                        # Print current environment information
                        echo "Rust + npm dev environment"
                        echo "Rust version: $(rustc --version)"
                        echo "Node.js version: $(node --version)"
                        echo "npm version: $(npm --version)"
                    '';
                };
            }
        );
}