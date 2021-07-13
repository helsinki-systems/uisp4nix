{ php, lib, fetchFromGitHub
, pcre2 }:
php.buildPecl rec {
  pname = "ds";
  version = "1.3.0";

  src = fetchFromGitHub {
    owner = "php-ds";
    repo = "ext-ds";
    rev = "v${version}";
    sha256 = "08fqn5q0p0d6qny08xkr2nnlkgmrr2chvda21ch231xnwd12s52p";
  };

  buildInputs = [
    pcre2
  ];

  internalDeps = lib.optional (lib.versionOlder php.version "8") php.extensions.json;

  meta = with lib; {
    description = "An extension providing efficient data structures for PHP 7";
    license = with licenses; [ mit ];
    maintainers = with maintainers; [ ajs124 das_j ] ++ teams.php.members;
  };
}
