#!/usr/bin/env bash
# IaC linter — fmt-check + validate (+ best-effort tflint) for the Terraform under
# _infra/. Read-only: never touches state, secrets, or any cloud (`terraform init
# -backend=false` + `validate` only). Calls the raw terraform binary so it bypasses
# the 1Password CLI wrapper (that wrapper only matters for plan/apply and would
# otherwise prompt for interactive auth). Override with TF_BIN / TFLINT_BIN.
#
# Packer linting is intentionally omitted — image builds are deferred in the cloud
# pivot and `packer` is not installed locally. Re-add a packer pass when golden-image
# builds return (the Proxmox-era templates under _infra/packer/ are archived-in-place).
#
# Usage:  _hack/scripts/iac-lint.sh
# Exit 0 = clean, 1 = a fmt/validate/tflint issue was found.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF="${TF_BIN:-$(command -v terraform || echo terraform)}"
TFLINT="${TFLINT_BIN:-$(command -v tflint || true)}"
TF_DIR="$ROOT/_infra/terraform"
TFLINT_CFG="$ROOT/.tflint.hcl"
fail=0
skipped=0

hr() { printf '\n=== %s ===\n' "$1"; }

hr "terraform (fmt-check + validate per dir)"
while IFS= read -r d; do
  rel="${d#"$ROOT"/}"
  if ! "$TF" fmt -check "$d" >/dev/null 2>&1; then
    echo "✗ fmt   $rel   (fix: terraform fmt $rel)"
    fail=1
  fi
  if ( cd "$d" && "$TF" init -backend=false -input=false >/dev/null 2>&1 ); then
    if ( cd "$d" && "$TF" validate >/dev/null 2>&1 ); then
      echo "✓ ok    $rel"
    else
      echo "✗ valid $rel"
      ( cd "$d" && "$TF" validate ) # re-run to show the error
      fail=1
    fi
  else
    echo "• skip  $rel   (terraform init failed — providers unavailable offline?)"
    skipped=$((skipped + 1))
  fi
done < <(
  find "$TF_DIR" -type d -name .terraform -prune \
    -o -name '*.tf' -printf '%h\n' | sort -u
)

if [ -n "$TFLINT" ]; then
  hr "tflint (best-effort per dir)"
  while IFS= read -r d; do
    rel="${d#"$ROOT"/}"
    if ( cd "$d" && "$TFLINT" --no-color --config "$TFLINT_CFG" >/dev/null 2>&1 ); then
      echo "✓ ok    $rel"
    else
      out="$( cd "$d" && "$TFLINT" --no-color --config "$TFLINT_CFG" 2>&1 )"
      # A missing-plugin/init error offline is a skip, not a failure.
      if printf '%s' "$out" | grep -qiE 'plugin|init|could not'; then
        echo "• skip  $rel   (run: tflint --init --config .tflint.hcl)"
        skipped=$((skipped + 1))
      else
        echo "✗ tflint $rel"
        printf '%s\n' "$out"
        fail=1
      fi
    fi
  done < <(
    find "$TF_DIR" -type d -name .terraform -prune \
      -o -name '*.tf' -printf '%h\n' | sort -u
  )
else
  echo "• tflint not found — skipping"
  skipped=$((skipped + 1))
fi

hr "result"
if [ "$fail" -ne 0 ]; then
  echo "❌ IaC lint found issues"
elif [ "$skipped" -ne 0 ]; then
  # Skips used to print a bullet and still exit 0, so a run that checked nothing
  # reported the same "passed" as a run that checked everything. Say so instead.
  echo "⚠️  IaC lint passed what it could, but SKIPPED $skipped check(s) — see • lines above."
  echo "   A skip is not a pass. Fix with: terraform init -backend=false (per root),"
  echo "   and tflint --init --config .tflint.hcl"
else
  echo "✅ IaC lint passed (fmt + validate + tflint, incl. the AWS ruleset)"
fi
exit "$fail"
