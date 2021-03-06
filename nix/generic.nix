{ pkgs, stdenv, lib, ocamlPackages, static ? false }:

rec {
  piaf = ocamlPackages.buildDune2Package {
    pname = "piaf";
    version = "0.0.1-dev";

    src = lib.gitignoreSource ./..;
    nativeBuildInputs = with ocamlPackages; [dune_2];
    propagatedBuildInputs = with ocamlPackages; [
      bigstringaf
      httpaf
      httpaf-lwt-unix
      h2
      h2-lwt-unix
      logs
      lwt_ssl
      ssl
      uri
    ];

    doCheck = false;

    meta = {
      description = "Client library for HTTP/1.X / HTTP/2 written entirely in OCaml.";
      license = stdenv.lib.licenses.bsd3;
    };
  };

  carl = stdenv.mkDerivation {
    name = "carl";
    version = "0.0.1-dev";

    src = lib.gitignoreSource ./..;

    nativeBuildInputs = with ocamlPackages; [dune_2 ocaml findlib];

    buildPhase = ''
      echo "running ${if static then "static" else "release"} build"
      dune build bin/carl.exe --display=short --profile=${if static then "static" else "release"}
    '';
    installPhase = ''
      mkdir -p $out/bin
      mv _build/default/bin/carl.exe $out/bin/carl
    '';

    buildInputs = with ocamlPackages; [
      piaf
      cmdliner
      fmt
      camlzip
      ezgzip
    ];

    doCheck = false;

    meta = {
      description = "Client library for HTTP/1.X / HTTP/2 written entirely in OCaml.";
      license = stdenv.lib.licenses.bsd3;
    };
  };
}

