{
  description = "CodeGraph – semantic code intelligence for AI agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        nodejs = pkgs.nodejs_24;

        codegraph = pkgs.buildNpmPackage {
          pname = "codegraph";
          version =
            (builtins.fromJSON (builtins.readFile ./package.json)).version;

          src = ./.;

          npmDeps = pkgs.fetchNpmDeps {
            src = ./.;
            hash = "sha256-GJfqzykgrgD/KCtf8LupRw31S2cCmwGCF/0PMpzaCrk=";
          };

          inherit nodejs;

          npmBuildScript = "build";

          # The build copies .wasm + schema.sql into dist/ via the
          # `copy-assets` npm script (called from `build`).  Nothing
          # extra to do here.

          installPhase = ''
            runHook preInstall

            # Application code
            mkdir -p $out/lib/codegraph
            cp -r dist $out/lib/codegraph/dist
            cp package.json $out/lib/codegraph/

            # Production node_modules — prune devDependencies that the
            # build step pulled in so the closure stays lean.
            npm prune --omit=dev
            find node_modules -mindepth 1 -maxdepth 1 -type d -empty -delete
            cp -r node_modules $out/lib/codegraph/node_modules

            # Launcher wrapper: injects --liftoff-only so tree-sitter's
            # large WASM grammars stay on V8's Liftoff baseline compiler
            # and never hit the turboshaft Zone OOM (issues #293/#298).
            mkdir -p $out/bin
            cat > $out/bin/codegraph <<'EOF'
#!/bin/sh
exec @node@ --liftoff-only @out@/lib/codegraph/dist/bin/codegraph.js "$@"
EOF
            substituteInPlace $out/bin/codegraph \
              --replace-fail '@node@' '${nodejs}/bin/node' \
              --replace-fail '@out@' "$out"
            chmod +x $out/bin/codegraph

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description =
              "Semantic code intelligence for AI agents — local-first knowledge graph over tree-sitter";
            homepage = "https://github.com/colbymchenry/codegraph";
            license = licenses.mit;
            mainProgram = "codegraph";
            platforms = platforms.unix;
          };
        };
      in {
        packages = {
          default = codegraph;
          inherit codegraph;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [ nodejs ];
        };
      });
}
