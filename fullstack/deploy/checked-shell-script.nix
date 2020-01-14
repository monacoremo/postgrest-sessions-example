{ writeTextFile, runtimeShell, stdenv, shellcheck}:

{ /*
   * Writes a shell script and checks it with shellcheck.
   *
   */
  write =
    name: text:
      writeTextFile {
        inherit name;
        executable = true;
        text =
          ''
            #!${runtimeShell}
            ${text}
          '';
        checkPhase =
          ''
            # check syntax
            ${stdenv.shell} -n $out

            # check for shellcheck recommendations
            ${shellcheck}/bin/shellcheck $out
          '';
      };

  /*
   * Writes a shell script to bin/<name> and checks it with shellcheck.
   *
   */
  writeBin =
      name: text:
        writeTextFile {
          inherit name;
          executable = true;
          destination = "/bin/${name}";
          text =
            ''
              #!${runtimeShell}
              ${text}
            '';
          checkPhase =
            ''
              # check syntax
              ${stdenv.shell} -n $out/bin/${name}

              # check for shellcheck recommendations
              ${shellcheck}/bin/shellcheck $out/bin/${name}
            '';
        };
}
