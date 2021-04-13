{ stdenv, stdenvNoCC, runCommandNoCC, fetchurl, dockerTools, nodejs, nodePackages, python3, yarn, yarn2nix-moretea, writeTextFile, pkgconfig, vips }:

let
  # nix run nixpkgs.skopeo -c skopeo --override-os linux --override-arch x86_64 inspect docker://docker.io/ubnt/unms:1.3.10 | jq -r '.Digest'
  version = "1.3.10";
  tag = version;

  unmsImage = dockerTools.pullImage {
    imageName = "ubnt/unms";
    imageDigest = "sha256:12fc462a722717d6b66dc52cba95ad15d29e5067aa5a8074817c515c16982a93";
    sha256 = "0qdd5alxl76g9wd23qgy018y4m772siw2gy5rj7vjh186s79mlfv";
    finalImageTag = tag;
  };

  # FIXME: https://github.com/NixOS/nixpkgs/pull/80068
  unmsServerSrc = runCommandNoCC "unms-server-src" {} ''
    mkdir $out
    tar xf ${dockerTools.runWithOverlay {
      name = "unms-app-${version}-src";
      diskSize = 2048;
      fromImage = unmsImage;
      postMount = ''
        mkdir -p $out
        set -x
        tar cf $out/layer.tar -C mnt/home/app/unms --exclude=node_modules --exclude=.wh..opq .
        echo ${version} > $out/VERSION
        touch $out/json # wat
        shopt -u extglob
      '';
    }}/layer.tar -C $out
  '';

  unms-server = yarn2nix-moretea.mkYarnPackage rec {
    src = unmsServerSrc;
    packageJSON = "${src}/package.json";
    yarnLock = "${src}/yarn.lock";
    yarnNix = ./yarn.nix;
    yarnFlags = yarn2nix-moretea.defaultYarnFlags ++ [ "--production" ];

    pkgConfig = let
      nodeGypRebuildPkg = {
        buildInputs = [ python3 nodePackages.node-gyp ];
        postInstall = ''
          node-gyp rebuild --nodedir="${nodejs}"
        '';
      };
    in {
      heapdump = nodeGypRebuildPkg;
      raw-socket = nodeGypRebuildPkg;
      sharp = {
        bcrypt = nodeGypRebuildPkg // {
          buildInputs = nodeGypRebuildPkg.buildInputs ++ [ nodePackages.node-pre-gyp ];
        };
        buildInputs = nodeGypRebuildPkg.buildInputs ++ [ pkgconfig vips ] ++ vips.buildInputs;
        postInstall = ''
          ${nodeGypRebuildPkg.postInstall}
          node install/dll-copy
        '';
      };
    };
  };
in {
  inherit unmsServerSrc unms-server;
}
