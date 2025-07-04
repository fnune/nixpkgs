{
  callPackage,
  lib,
  jq,
  runCommand,
  writeText,
  python3,
}:
{
  combinedDir,
  touchedFilesJson,
  githubAuthorId,
  byName ? false,
}:
let
  /*
    Derivation that computes which packages are affected (added, changed or removed) between two revisions of nixpkgs.
    Note: "platforms" are "x86_64-linux", "aarch64-darwin", ...

    ---
    Inputs:
    - beforeDir, afterDir: The evaluation result from before and after the change.
      They can be obtained by running `nix-build -A ci.eval.full` on both revisions.

    ---
    Outputs:
      - changed-paths.json: Various information about the changes:
        {
          attrdiff: {
            added: ["package1"],
            changed: ["package2", "package3"],
            removed: ["package4"],
          },
          labels: {
            "10.rebuild-darwin: 1-10": true,
            "10.rebuild-linux: 1-10": true
          },
          rebuildsByKernel: {
            darwin: ["package1", "package2"],
            linux: ["package1", "package2", "package3"]
          },
          rebuildCountByKernel: {
            darwin: 2,
            linux: 3,
          },
          rebuildsByPlatform: {
            aarch64-darwin: ["package1", "package2"],
            aarch64-linux: ["package1", "package2"],
            x86_64-linux: ["package1", "package2", "package3"],
            x86_64-darwin: ["package1"],
          },
        }
      - step-summary.md: A markdown render of the changes

    ---
    Implementation details:

    Helper functions can be found in ./utils.nix.
    Two main "types" are important:

    - `packagePlatformPath`: A string of the form "<PACKAGE_PATH>.<PLATFORM>"
      Example: "python312Packages.numpy.x86_64-linux"

    - `packagePlatformAttr`: An attrs representation of a packagePlatformPath:
      Example: { name = "python312Packages.numpy"; platform = "x86_64-linux"; }
  */
  inherit (import ./utils.nix { inherit lib; })
    groupByKernel
    convertToPackagePlatformAttrs
    groupByPlatform
    extractPackageNames
    getLabels
    ;

  # Attrs
  # - keys: "added", "changed" and "removed"
  # - values: lists of `packagePlatformPath`s
  diffAttrs = builtins.fromJSON (builtins.readFile "${combinedDir}/combined-diff.json");

  rebuilds = diffAttrs.added ++ diffAttrs.changed;
  rebuildsPackagePlatformAttrs = convertToPackagePlatformAttrs rebuilds;

  changed-paths =
    let
      rebuildsByPlatform = groupByPlatform rebuildsPackagePlatformAttrs;
      rebuildsByKernel = groupByKernel rebuildsPackagePlatformAttrs;
      rebuildCountByKernel = lib.mapAttrs (
        kernel: kernelRebuilds: lib.length kernelRebuilds
      ) rebuildsByKernel;
    in
    writeText "changed-paths.json" (
      builtins.toJSON {
        attrdiff = lib.mapAttrs (_: extractPackageNames) diffAttrs;
        inherit
          rebuildsByPlatform
          rebuildsByKernel
          rebuildCountByKernel
          ;
        labels =
          getLabels rebuildCountByKernel
          # Sets "10.rebuild-*-stdenv" label to whether the "stdenv" attribute was changed.
          // lib.mapAttrs' (
            kernel: rebuilds: lib.nameValuePair "10.rebuild-${kernel}-stdenv" (lib.elem "stdenv" rebuilds)
          ) rebuildsByKernel
          # Set the "11.by: package-maintainer" label to whether all packages directly
          # changed are maintained by the PR's author.
          # (https://github.com/NixOS/ofborg/blob/df400f44502d4a4a80fa283d33f2e55a4e43ee90/ofborg/src/tagger.rs#L83-L88)
          // {
            "11.by: package-maintainer" =
              maintainers ? ${githubAuthorId}
              && lib.all (lib.flip lib.elem maintainers.${githubAuthorId}) (
                lib.flatten (lib.attrValues maintainers)
              );
          };
      }
    );

  maintainers = callPackage ./maintainers.nix { } {
    changedattrs = lib.attrNames (lib.groupBy (a: a.name) rebuildsPackagePlatformAttrs);
    changedpathsjson = touchedFilesJson;
    inherit byName;
  };
in
runCommand "compare"
  {
    nativeBuildInputs = [
      jq
      (python3.withPackages (
        ps: with ps; [
          numpy
          pandas
          scipy
        ]
      ))

    ];
    maintainers = builtins.toJSON maintainers;
    passAsFile = [ "maintainers" ];
    env = {
      BEFORE_DIR = "${combinedDir}/before";
      AFTER_DIR = "${combinedDir}/after";
    };
  }
  ''
    mkdir $out

    cp ${changed-paths} $out/changed-paths.json


    if jq -e '(.attrdiff.added | length == 0) and (.attrdiff.removed | length == 0)' "${changed-paths}" > /dev/null; then
      # Chunks have changed between revisions
      # We cannot generate a performance comparison
      {
        echo
        echo "# Performance comparison"
        echo
        echo "This compares the performance of this branch against its pull request base branch (e.g., 'master')"
        echo
        echo "For further help please refer to: [ci/README.md](https://github.com/NixOS/nixpkgs/blob/master/ci/README.md)"
        echo
      } >> $out/step-summary.md

      python3 ${./cmp-stats.py} >> $out/step-summary.md

    else
      # Package chunks are the same in both revisions
      # We can use the to generate a performance comparison
      {
        echo
        echo "# Performance Comparison"
        echo
        echo "Performance stats were skipped because the package sets differ between the two revisions."
        echo
        echo "For further help please refer to: [ci/README.md](https://github.com/NixOS/nixpkgs/blob/master/ci/README.md)"
      } >> $out/step-summary.md
    fi

    {
      echo
      echo "# Packages"
      echo
      jq -r -f ${./generate-step-summary.jq} < ${changed-paths}
    } >> $out/step-summary.md

    cp "$maintainersPath" "$out/maintainers.json"
  ''
