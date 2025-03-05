{ system ? builtins.currentSystem }:

with (import (fetchTarball {
  name = "nixpkgs-23.05";
  url = "https://github.com/nixos/nixpkgs/archive/23.05.tar.gz";
  sha256 = "10wn0l08j9lgqcw8177nh2ljrnxdrpri7bp0g7nvrsn9rkawvlbf";
}) { inherit system; });


let
  requiredNixVersion = "2.3";

  pwd = builtins.getEnv "PWD";
in

if lib.versionOlder builtins.nixVersion requiredNixVersion == true then
  abort "This project requires Nix >= ${requiredNixVersion}, please run 'nix-channel --update && nix-env -i nix'."
else

  mkShell {
    buildInputs = [
      stdenv
      git
      cacert

      # Ruby and Rails dependencies
      ruby_3_2

      # Services
      overmind
      redis

    ] ++ lib.optional (!stdenv.isDarwin) [
      # linux-only packages
      glibcLocales
    ];

    HOST = "127.0.0.24";
    REDIS_URL="redis://127.0.0.24:6379/1";
    BUNDLE_PATH = "vendor/bundle";
  }
