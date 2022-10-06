{ system ? builtins.currentSystem }:

with (import (fetchTarball {
  name = "nixpkgs-21.11";
  url = "https://github.com/nixos/nixpkgs/archive/21.11.tar.gz";
  sha256 = "162dywda2dvfj1248afxc45kcrg83appjd0nmdb541hl7rnncf02";
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
      ruby_2_7.devEnv
      bundler

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
