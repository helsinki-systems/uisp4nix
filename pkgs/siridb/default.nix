{ stdenv, fetchFromGitHub
, libcleri
, libuuid
, libuv
, pcre2
, yajl
}:
stdenv.mkDerivation rec {
  pname = "siridb";
  version = "2.0.44";

  src = fetchFromGitHub {
    owner = pname;
    repo = "${pname}-server";
    rev = version;
    sha256 = "0fslvvsjwhm4w2xkiz4hb6igh9i9xdrsbs1l3j4m73bzk8x7h41m";
  };

  buildInputs = [
    libcleri
    libuuid
    libuv
    pcre2
    yajl
  ];

  patches = [
    ./makefile.patch
  ];

  makeFlags = [
    "INSTALL_PATH=${placeholder "out"}"
  ];

  preBuild = ''
    cd Release
  '';
  preInstall = ''
    mkdir -p $out/bin
  '';
}
