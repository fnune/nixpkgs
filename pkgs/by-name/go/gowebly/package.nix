{
  lib,
  buildGo124Module,
  fetchFromGitHub,
  versionCheckHook,
  nix-update-script,
}:

buildGo124Module rec {
  pname = "gowebly";
  version = "3.0.4";

  src = fetchFromGitHub {
    owner = "gowebly";
    repo = "gowebly";
    tag = "v${version}";
    hash = "sha256-oz/O5scGJigWjrmA2wnagDbf+epvwuyRI2CaSQY8K5I=";
  };

  vendorHash = "sha256-BDdH6cFicbjT2WOldNRc8NcFKrIaeqy+mw113PRnwa8=";

  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
  ];

  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "doctor";
  doInstallCheck = true;

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "CLI tool to create web applications with Go backend";
    longDescription = ''
      A CLI tool that makes it easy to create web applications
      with Go on the backend, using htmx, hyperscript or Alpine.js,
      and the most popular CSS frameworks on the frontend.
    '';
    homepage = "https://gowebly.org";
    changelog = "https://github.com/gowebly/gowebly/releases/tag/v${version}";
    license = lib.licenses.asl20;
    mainProgram = "gowebly";
    maintainers = with lib.maintainers; [ cterence ];
  };
}
