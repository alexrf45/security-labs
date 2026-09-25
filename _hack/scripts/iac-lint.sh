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
fail=0

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
  fi
done < <(
  find "$TF_DIR" -type d -name .terraform -prune \
    -o -name '*.tf' -printf '%h\n' | sort -u
)

if [ -n "$TFLINT" ]; then
  hr "tflint (best-effort per dir)"
  while IFS= read -r d; do
    rel="${d#"$ROOT"/}"
    if ( cd "$d" && "$TFLINT" --no-color >/dev/null 2>&1 ); then
      echo "✓ ok    $rel"
    else
      out="$( cd "$d" && "$TFLINT" --no-color 2>&1 )"
      # A missing-plugin/init error offline is a skip, not a failure.
      if printf '%s' "$out" | grep -qiE 'plugin|init|could not'; then
        echo "• skip  $rel   (tflint needs --init / plugins offline)"
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
fi

hr "result"
[ "$fail" -eq 0 ] && echo "✅ IaC lint passed" || echo "❌ IaC lint found issues"
exit "$fail"
