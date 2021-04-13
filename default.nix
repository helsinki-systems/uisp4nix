{ pkgs ? import <nixpkgs> {} }:
let
  server = pkgs.callPackage ./unms-server.nix { };
in {
  inherit (server) unmsServerSrc unms-server;
}
