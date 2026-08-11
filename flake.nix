{
  description = "Sidekiq middleware extending RetryJobs to allow silent errors";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "aarch64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs supportedSystems (system: f nixpkgs.legacyPackages.${system});
      host = "127.0.0.24";
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          buildInputs = with pkgs; [
            git
            cacert
            ruby_4_0

            # Services
            overmind
            redis
          ] ++ lib.optionals stdenv.isLinux [
            glibcLocales
          ];

          HOST = host;
          REDIS_URL = "redis://${host}:6379/1";
          BUNDLE_PATH = "vendor/bundle";
        };
      });
    };
}
