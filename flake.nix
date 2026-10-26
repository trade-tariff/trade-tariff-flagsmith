{
  outputs =
    _:
    let
      pkgs =
        import
          (builtins.fetchTree {
            type = "github";
            owner = "NixOS";
            repo = "nixpkgs";
            rev = "55bfb4d7437bd4e09ab7cba58a43bd68eb310044";
            narHash = "sha256-jBYGPi4udQ9uo4KQp9m2J0546nJVQitG15gvZSaVVAs=";
          })
          {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
      reviewTools = import (builtins.fetchTree {
        type = "github";
        owner = "NixOS";
        repo = "nixpkgs";
        rev = "4a29d733e8a7d5b824c3d8c958a946a9867b3eb2";
        narHash = "sha256-f+JACbTqzZ+G92DSnXOUGRhGANb8Blh7CoeYOeBF8/U=";
      }) { system = "x86_64-linux"; };
      reviewGruntworkHooks = builtins.fetchTree {
        type = "github";
        owner = "gruntwork-io";
        repo = "pre-commit";
        rev = "40f924cd642f5dc98d12bd97b07f3752223553da"; # v0.1.30
        narHash = "sha256-65XIHgVOMOGpFCIFfBjkIq33kSC98sFDGleXAgFDYpM=";
      };
      reviewTerraformHooks = builtins.fetchTree {
        type = "github";
        owner = "antonbabenko";
        repo = "pre-commit-terraform";
        rev = "d61ded22bf9aa0f757303ebcbb0d6d71c4b54015"; # v1.106.0
        narHash = "sha256-IPONqvEUoGrsnQkD0RTLW28QKoKqv8wf/ooExmSTJmE=";
      };
      reviewTrufflehogScan = pkgs.writeShellScript "trufflehog-pre-commit" ''
        set -euo pipefail
        exclude_file="$(mktemp)"
        trap 'rm -f "$exclude_file"' EXIT
        printf '%s\n' '(^|/)\.git(/|$)' '(^|/)\.terraform(/|$)' '(^|/)\.terragrunt-cache(/|$)' > "$exclude_file"
        while IFS= read -r ignored; do
          [ -n "$ignored" ] || continue
          escaped="$(printf '%s' "''${ignored%/}" | sed 's/[][(){}.^$*+?|\\]/\\&/g')"
          case "$ignored" in
            */) printf '(^|/)%s(/|$)\n' "$escaped" >> "$exclude_file" ;;
            *) printf '(^|/)%s$\n' "$escaped" >> "$exclude_file" ;;
          esac
        done < <(git ls-files --others --ignored --exclude-standard --directory)
        exec ${pkgs.trufflehog}/bin/trufflehog filesystem "$(pwd -P)" --exclude-paths="$exclude_file" --results=verified,unknown --fail
      '';
      reviewPreCommitConfig = pkgs.writeText "review-pre-commit.json" (
        builtins.toJSON {
          repos = [
            {
              repo = "local";
              hooks = [
                {
                  id = "terragrunt-hcl-fmt";
                  name = "Terragrunt hcl fmt";
                  language = "system";
                  entry = "${reviewGruntworkHooks}/hooks/terragrunt-hcl-fmt.sh";
                  files = "\\.hcl$";
                  exclude = "(?x)^(\n  \\.terraform\\/.*|\n  \\.terragrunt-cache\\/.*|\n)$\n";
                }
                {
                  id = "terraform_fmt";
                  name = "Terraform fmt";
                  language = "system";
                  entry = "${reviewTerraformHooks}/hooks/terraform_fmt.sh";
                  files = "\\.(tf|tofu|tfvars|(tftest|tofutest|tfmock|tfquery)\\.hcl)$";
                  exclude = "\\.terraform/.*$";
                }
                {
                  id = "terraform_validate";
                  name = "Terraform validate";
                  language = "system";
                  entry = "${reviewTerraformHooks}/hooks/terraform_validate.sh";
                  files = "\\.(tf|tofu|tfvars|terraform\\.lock\\.hcl)$";
                  exclude = "\\.terraform/.*$";
                  require_serial = true;
                  args = [
                    "--hook-config=--parallelism-limit=1"
                    "--tf-init-args=-lockfile=readonly"
                  ];
                }
                {
                  id = "terraform_tflint";
                  name = "Terraform validate with tflint";
                  language = "system";
                  entry = "${reviewTerraformHooks}/hooks/terraform_tflint.sh";
                  files = "\\.(tf|tofu|tfvars)$";
                  exclude = "\\.terraform/.*$";
                  require_serial = true;
                  args = [
                    "--hook-config=--parallelism-limit=1"
                    "--tf-init-args=-lockfile=readonly"
                  ];
                }
                {
                  id = "trailing-whitespace";
                  name = "trim trailing whitespace";
                  language = "system";
                  entry = "${reviewTools.python3Packages.pre-commit-hooks}/bin/trailing-whitespace-fixer";
                  types = [ "text" ];
                  stages = [
                    "pre-commit"
                    "pre-push"
                    "manual"
                  ];
                }
                {
                  id = "end-of-file-fixer";
                  name = "fix end of files";
                  language = "system";
                  entry = "${reviewTools.python3Packages.pre-commit-hooks}/bin/end-of-file-fixer";
                  types = [ "text" ];
                  stages = [
                    "pre-commit"
                    "pre-push"
                    "manual"
                  ];
                }
                {
                  id = "check-yaml";
                  name = "check yaml";
                  language = "system";
                  entry = "${reviewTools.python3Packages.pre-commit-hooks}/bin/check-yaml";
                  types = [ "yaml" ];
                }
                {
                  id = "check-merge-conflict";
                  name = "check for merge conflicts";
                  language = "system";
                  entry = "${reviewTools.python3Packages.pre-commit-hooks}/bin/check-merge-conflict";
                  types = [ "text" ];
                }
                {
                  id = "actionlint-docker";
                  name = "Lint GitHub Actions workflow files";
                  language = "system";
                  entry = "${reviewTools.actionlint}/bin/actionlint";
                  types = [ "yaml" ];
                  files = "^\\.github/workflows/";
                }
                {
                  id = "trufflehog";
                  name = "TruffleHog";
                  language = "system";
                  entry = "${reviewTrufflehogScan}";
                  stages = [
                    "pre-commit"
                    "pre-push"
                  ];
                }
              ];
            }
          ];
        }
      );
      reviewEnvironment = ''
        if [ "''${REVIEW_SANDBOX:-}" != 1 ] || [ "$PWD" != /workspace ]; then exit 64; fi
        for name in "''${!AWS_@}" "''${!TF_CLI_ARGS@}"; do if [ -n "$name" ]; then unset "$name"; fi; done
        export TMPDIR=/workspace/.review/tmp PRE_COMMIT_HOME=/workspace/.review/pre-commit
        export TF_CLI_CONFIG_FILE=/workspace/.review/terraform.rc TF_IN_AUTOMATION=1 TF_INPUT=0 CHECKPOINT_DISABLE=1
        export AWS_EC2_METADATA_DISABLED=true AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null AWS_REGION=eu-west-2
        unset TF_PLUGIN_CACHE_DIR
        mkdir -p "$TMPDIR"
        files="$(git ls-files '*.tf')"
        test -n "$files"
        mapfile -t roots < <(printf '%s\n' "$files" | while IFS= read -r file; do dirname "$file"; done | sort -u)
      '';
    in
    {
      devShells.x86_64-linux.review = pkgs.mkShell {
        shellHook = "";
        packages = [
          pkgs.gitMinimal
          pkgs.terraform
          pkgs.terragrunt
          pkgs.tflint
          reviewTools.pre-commit
          reviewTools.shellcheck
          pkgs.coreutils
          pkgs.findutils
          pkgs.gnugrep
          pkgs.gnused
          pkgs.gawk
          pkgs.jq
          pkgs.util-linux
        ];
        nativeBuildInputs = [
          (pkgs.writeShellApplication {
            name = "review-bootstrap";
            text = reviewEnvironment + ''
              printf 'disable_checkpoint = true\nprovider_installation {\n filesystem_mirror {\n path = "/deps/terraform-inputs/providers"\n include = ["registry.terraform.io/*/*"]\n }\n}\n' > "$TF_CLI_CONFIG_FILE"
              for root in "''${roots[@]}"; do
                mkdir -p "$root/.terraform/modules"
                cp "/deps/terraform-inputs/roots/$root/lock.hcl" "$root/.terraform.lock.hcl"
                if [ -f "/deps/terraform-inputs/roots/$root/modules.json" ]; then cp "/deps/terraform-inputs/roots/$root/modules.json" "$root/.terraform/modules/modules.json"; fi
                terraform -chdir="$root" init -backend=false -input=false -lockfile=readonly -no-color
              done
            '';
          })
          (pkgs.writeShellApplication {
            name = "review-check";
            text = reviewEnvironment + ''
              status=0
              pre-commit run --all-files --config ${reviewPreCommitConfig} || status=$?
              terraform fmt -check -recursive || status=$?
              if [ -n "$(git ls-files '*terragrunt.hcl')" ]; then terragrunt hcl fmt --check || status=$?; fi
              for root in "''${roots[@]}"; do
                terraform -chdir="$root" validate -no-color || status=$?
                tflint --chdir="$root" --call-module-type=all || status=$?
              done
              if [ -n "$(git ls-files '*.tftest.*')" ]; then echo 'Blocked: Terraform test files need an explicit mocked-plan safety review.' >&2; exit 78; fi
              if [ "$status" -ne 0 ]; then exit "$status"; fi
              echo 'Live infrastructure plans and applies are outside offline code validation.'
              exit 0
            '';
          })
        ];
        TZDIR = "${pkgs.tzdata.outPath}/share/zoneinfo";
        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      };
    };
}
