{ stdenv, runCommandNoCC, dockerTools, php, callPackage }:

let
  # nix run nixpkgs.skopeo -c skopeo --override-os linux --override-arch x86_64 inspect docker://docker.io/ubnt/unms-crm:3.3.11 | jq -r '.Digest'
  version = "3.3.11";
  tag = version;

  ucrmImage = dockerTools.pullImage {
    imageName = "ubnt/unms-crm";
    imageDigest = "sha256:897fdd2d5034b72b3ca67d061cb2f1a647f23afa6f0e01d00dfe7d5dedd497fc";
    sha256 = "1j7sz2wha85kdmqx7xs5h05bq0xfvn1cm1zl3z9fwz3zngwc725c";
    finalImageTag = tag;
  };

  # FIXME: https://github.com/NixOS/nixpkgs/pull/80068
  ucrmSrc = runCommandNoCC "ucrm-src" rec {
    phpEnv = php.buildEnv {
      extensions = { enabled, all }: with all; enabled ++ [
        apcu
        (callPackage ./php-ds.nix { })  # TODO: upstream to nixpkgs
      ];
    };
    buildInputs = [ phpEnv ];
  } ''
    mkdir $out
    tar xf ${dockerTools.runWithOverlay {
      name = "ucrm-${version}-src";
      diskSize = 2048;
      fromImage = ucrmImage;
      postMount = ''
        mkdir -p $out
        tar cf $out/layer.tar -C mnt/usr/src/ucrm --exclude=.wh..opq .
        # -C ../../../tmp .
        echo ${version} > $out/VERSION
        touch $out/json # wat
        shopt -u extglob
      '';
    }}/layer.tar -C $out

    # general patching of paths
    patchShebangs $out
    find $out/scripts -type f -exec sed -i "s_/usr/src/ucrm_''${out}_g" {} +
    find $out -type f -and '(' -name '*.sh' -or -name '*.php' ')' -exec sed -i "s_/data/log/ucrm_/var/log/ucrm_g" {} +
    find $out -type f -and '(' -name '*.sh' -or -name '*.php' -or -name '*.yml' ')' -exec sed -i "s_/data/ucrm_/var/lib/ucrm_g" {} +

    # data
    rmdir $out/app/data
    ln -s /var/lib/ucrm/data $out/app/data
    mv $out/app/config/parameters.yml{,.orig}
    ln -s /run/ucrm/parameters.yml $out/app/config/parameters.yml
    sed -i "s_''${out}/app/config/parameters.yml_/run/ucrm/parameters.yml_g" $out/scripts/parameters.sh
    sed -i "s|^NODE_AUTH_KEY|#NODE_AUTH_KEY|" $out/scripts/parameters.sh

    # cache
    rm -rf $out/app/cache
    ln -s /var/cache/ucrm $_

    # logs
    rm -rf $out/app/logs
    ln -s /var/log/ucrm $_
  '';

  # TODO: composer2nix & yarn2nix
in {
  inherit ucrmSrc;
}
