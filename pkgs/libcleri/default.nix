{ stdenv, fetchFromGitHub
, pcre2
}:
stdenv.mkDerivation rec {
  pname = "libcleri";
  version = "0.12.1";

  src = fetchFromGitHub {
    owner = "transceptor-technology";
    repo = pname;
    rev = version;
    sha256 = "1pcjxd2hx0zxb7xdpazcq9jnpdlisvj2l0rrldl17vzi8yzcy25a";
  };

  buildInputs = [ pcre2 ];

  makeFlags = [
    "INSTALL_PATH=${placeholder "out"}"
  ];

  preBuild = ''
    cd Release
  '';
  preInstall = ''
    mkdir -p $out/{include,lib}
  '';
}
