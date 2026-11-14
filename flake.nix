{
  description = "Modern Shell — modular, colorful zsh environment with snapshots and the msh TUI/CLI manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        version = pkgs.lib.removeSuffix "\n" (builtins.readFile ./shell/VERSION);

        msh = pkgs.buildGoModule {
          pname = "modern-shell";
          inherit version;
          src = ./.;
          # Recompute after changing go.mod/go.sum: `make vendor-hash` (no nix needed).
          vendorHash = "sha256-23DThOAM/yVVTpT4rnlbQHomxXGZO0o1mYkPh42F6ho=";
          subPackages = [ "cmd/msh" ];
          env.CGO_ENABLED = 0;
          ldflags = [ "-s" "-w" "-X main.version=${version}" ];

          nativeBuildInputs = [ pkgs.installShellFiles pkgs.makeWrapper ];
          # Unit tests need only the store package (the TUI tests render with glamour).
          checkPhase = ''
            runHook preCheck
            go test ./internal/store/
            runHook postCheck
          '';
          nativeCheckInputs = [ pkgs.zsh ];

          postInstall = ''
            share=$out/share/modern-shell
            mkdir -p $share
            cp -r shell configs install.sh uninstall.sh $share/
            makeWrapper ${pkgs.bash}/bin/bash $out/bin/msh-setup \
              --add-flags "$share/install.sh --no-binary" \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.zsh pkgs.coreutils pkgs.gnugrep pkgs.gnused ]}
            installShellCompletion --cmd msh \
              --zsh  <($out/bin/msh completion zsh) \
              --bash <($out/bin/msh completion bash) \
              --fish <($out/bin/msh completion fish)
            install -Dm644 LICENSE -t $out/share/licenses/modern-shell
            install -Dm644 README.md docs/*.md -t $out/share/doc/modern-shell
          '';

          meta = with pkgs.lib; {
            description = "Modular, colorful zsh environment with snapshots and the msh TUI/CLI manager";
            homepage = "https://github.com/Szmelc-INC/Modern-Shell";
            license = licenses.mit;
            mainProgram = "msh";
            platforms = platforms.unix;
          };
        };
      in {
        packages.default = msh;
        packages.modern-shell = msh;

        apps.default = { type = "app"; program = "${msh}/bin/msh"; };
        apps.setup = { type = "app"; program = "${msh}/bin/msh-setup"; };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ go gopls gotools zsh bash fzf zoxide eza bat fd ripgrep tmux nano shellcheck python3 ];
          shellHook = ''echo "Modern Shell dev shell — make help"'';
        };
      });
}
