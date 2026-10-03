#!/usr/bin/env bash
# Regression tests for guard-mutations.sh, the PreToolUse safety control.
#
# This exists because the guard is deliberately tuned to fire LESS often than a naive
# substring match: heredoc bodies are excluded so that authoring the deployment runbook
# (whose subject matter is the apply commands) is not blocked. Every exclusion is a place
# a real mutation could hide, so both directions are asserted here — a future edit that
# widens the hole should fail this file rather than pass silently.
#
# Usage: _hack/scripts/guard-mutations.test.sh
# Exit 0 = all cases behave as specified, 1 = at least one regression.
set -uo pipefail

GUARD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/guard-mutations.sh"
pass=0
fail=0

# check <expect: block|allow> <label> <command>
check() {
  local expect="$1" label="$2" cmd="$3" got rc
  # Build the PreToolUse payload the way Claude Code does: JSON on stdin.
  rc=0
  printf '%s' "$(jq -nc --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}')" \
    | "$GUARD" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] && got=block || got=allow
  if [ "$got" = "$expect" ]; then
    pass=$((pass + 1))
    printf '  ok    %-42s %s\n' "$label" "$expect"
  else
    fail=$((fail + 1))
    printf '  FAIL  %-42s expected %s, got %s (rc=%s)\n' "$label" "$expect" "$got" "$rc"
  fi
}

printf '\n=== must BLOCK: real mutations ===\n'
check block "plain apply"                 'terraform apply'
check block "apply with flags"            'terraform apply -auto-approve'
check block "destroy under op run"        'op run -- terraform destroy'
check block "env wrapper"                 'op run -- env TF_VAR_x=1 terraform apply'
check block "after cd in an && chain"     'cd _infra/terraform/aws && terraform apply'
check block "chained after a read cmd"    'terraform validate; terraform apply'
check block "tofu destroy"                'tofu destroy'
check block "state surgery"               'terraform state rm aws_vpc.range'
check block "state surgery via -chdir"    'terraform -chdir=_infra/terraform/aws/ops-tier state rm aws_eip.router'
check block "state push via -chdir"       'op run -- terraform -chdir=x state push new.tfstate'
check block "packer build"                'packer build image.pkr.hcl'
check block "aws terminate"               'aws ec2 terminate-instances --instance-ids i-1'
check block "aws create-tags"             'aws ec2 create-tags --resources i-1 --tags k=v'
check block "aws with global flags"       'aws --region us-east-1 ec2 terminate-instances --instance-ids i-1'
check block "aws with --flag=value"       'aws --region=us-east-1 ec2 delete-volume --volume-id v-1'
check block "heredoc piped to bash"       "$(printf 'cat <<%sEOF%s | bash\nterraform apply\nEOF' "'" "'")"
check block "heredoc piped to sudo sh"    "$(printf 'cat <<EOF | sudo sh\nterraform destroy\nEOF')"
check block "real apply after a heredoc"  "$(printf 'cat <<%sEOF%s > doc.md\nsome text\nEOF\nterraform apply' "'" "'")"

printf '\n=== must ALLOW: read-only ===\n'
check allow "validate"                    'terraform validate'
check allow "fmt"                         'terraform fmt -recursive .'
check allow "plan"                        'op run -- terraform plan'
check allow "aws describe"                'aws ec2 describe-instances --filters Name=x,Values=y'
check allow "aws get"                     'aws ec2 get-ebs-encryption-by-default'
check allow "tflint"                      'tflint --config .tflint.hcl'
check allow "infracost"                   'infracost breakdown --path .'
# The widened state-surgery pattern must not swallow the read-only state subcommands
# /lab-status depends on.
check allow "state list via -chdir"       'terraform -chdir=_infra/terraform/aws/ops-tier state list'
check allow "state show"                  'terraform state show aws_vpc.range'
# The verb appears only inside a --filters VALUE, never in the operation position.
check allow "mutating word in a filter"   'aws ec2 describe-instances --filters Name=tag:Name,Values=create-foo'
check allow "mutating word in a query"    'aws ec2 describe-volumes --query Volumes[?Tags[?Value==`delete-me`]]'

printf '\n=== must ALLOW: authoring docs that quote the commands ===\n'
check allow "python heredoc w/ apply"     "$(printf 'python3 - <<%sPY%s\ns = "op run -- terraform apply"\nprint(s)\nPY' "'" "'")"
check allow "double-quoted delimiter"     "$(printf 'cat <<"EOF" > runbook.md\nop run -- terraform apply\nEOF')"
check allow "dash heredoc"                "$(printf 'cat <<-EOF > f\n\tterraform destroy\n\tEOF')"
check allow "two heredocs"                "$(printf 'cat <<%sA%s > x\nterraform apply\nA\ncat <<%sB%s > y\npacker build z\nB' "'" "'" "'" "'")"
check allow "heredoc then a read cmd"     "$(printf 'cat <<%sEOF%s > doc.md\nterraform apply\nEOF\nterraform validate' "'" "'")"

printf '\n=== result ===\n'
if [ "$fail" -eq 0 ]; then
  echo "✅ guard-mutations: $pass/$((pass + fail)) cases behave as specified"
  exit 0
fi
echo "❌ guard-mutations: $fail of $((pass + fail)) cases REGRESSED"
exit 1
