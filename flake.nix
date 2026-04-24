{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          sources = builtins.fromJSON (builtins.readFile ./versions.json);
          source = sources.${system};
        in
        {
          default = pkgs.stdenvNoCC.mkDerivation {
            pname = "codex";
            inherit (sources) version;

            src = pkgs.fetchurl { inherit (source) url hash; };

            nativeBuildInputs = [ pkgs.makeWrapper ];

            dontUnpack = true;

            installPhase = ''
              tar xzf $src
              install -Dm755 codex-* $out/bin/codex
            '';

            postFixup = ''
              wrapProgram $out/bin/codex \
                --argv0 codex \
                --set CODEX_DISABLE_AUTO_UPDATE 1
            '';

            dontStrip = true;

            meta = with pkgs.lib; {
              description = "OpenAI Codex CLI — an agentic coding assistant in your terminal";
              homepage = "https://github.com/openai/codex";
              license = licenses.asl20;
              mainProgram = "codex";
              platforms = systems;
            };
          };
        }
      );
    };
}
