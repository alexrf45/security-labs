#!/usr/bin/env bash
# PreToolUse guard — blocks Claude from running state-mutating / cost-incurring
# infra commands. The operating model (CLAUDE.md, .claude/rules/terraform.md) is:
# the USER runs plan/apply/build/destroy manually, wrapped in `op run --`. Claude
# validates offline only. This makes that rule mechanical, not honor-system.
#
# Contract: Claude Code passes the tool call as JSON on stdin. Exit 2 = block the
# call (stderr is surfaced to the model). Exit 0 = allow. Fail-open on parse error
# so a malformed payload never wedges the session.
#
# Matching is invocation-aware: the command is split into segments on shell
# separators (; && || | and newlines); each segment's leading wrapper tokens
# (`op run --`, `sudo`, `env`, VAR=val) are stripped; then the segment is blocked
# only if it *starts with* a guarded binary AND names a mutating subcommand.
# Read-only calls (`terraform validate`, `aws ec2 describe-*`) never match.
#
# Guarded binaries are terraform/tofu, packer and aws only. hcloud/az/gcloud branches
# were removed: AWS is the sole provider (ADR-0011) and those CLIs are absent and not
# needed (cloud-inventory.md), so they guarded nothing. Re-add if a provider returns.
#
# HEREDOC BODIES ARE EXCLUDED (see strip_heredocs). Segmenting on newlines used to
# make a heredoc line that merely reads `terraform apply` into its own segment,
# indistinguishable from a real invocation — which blocked authoring the deployment
# runbook, whose subject matter *is* those commands. The exception is a heredoc piped
# into a shell: that body really does execute, so it is scanned instead of stripped.
set -uo pipefail

payload="$(cat)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

block() {
  echo "BLOCKED by guard-mutations.sh: $1" >&2
  echo "Per .claude/rules/terraform.md, the user runs this manually via 'op run -- ...'." >&2
  echo "Claude runs offline checks only (terraform validate/fmt, tflint, infracost breakdown)." >&2
  exit 2
}

# Remove heredoc bodies, keeping the line that opens them. Quoted delimiters are
# normalised first (<<'EOF' / <<"EOF" / <<-EOF -> <<EOF) so the awk pass needs no
# quote handling.
strip_heredocs() {
  sed -E "s/<<-?[[:space:]]*(['\"])?([A-Za-z_][A-Za-z0-9_]*)(['\"])?/<<\2/g" \
  | awk '
      { if (indoc) { if ($0 ~ ("^[ \t]*" delim "[ \t]*$")) indoc = 0; next } }
      { print }
      { if (match($0, /<<[A-Za-z_][A-Za-z0-9_]*/)) {
          delim = substr($0, RSTART + 2, RLENGTH - 2); indoc = 1 } }
    '
}

# A heredoc fed to an interpreter is executable, so do not strip it.
if printf '%s' "$cmd" | grep -qE '\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh|dash|ksh)([[:space:]]|$)'; then
  scanned="$cmd"
else
  scanned="$(printf '%s' "$cmd" | strip_heredocs)"
fi

# Split into segments on shell separators, evaluate each independently.
segments="$(printf '%s' "$scanned" | tr '\n;|&' '\n\n\n\n')"

while IFS= read -r seg; do
  # Strip leading wrappers: `op run [...] --`, sudo, env, and VAR=val assignments.
  s="$(printf '%s' "$seg" \
        | sed -E 's/^[[:space:]]+//' \
        | sed -E 's/^op[[:space:]]+run([[:space:]]+[^-][^[:space:]]*)*[[:space:]]+--[[:space:]]+//' \
        | sed -E 's/^(sudo|env|command|nice|nohup|time)[[:space:]]+//' \
        | sed -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)+//' \
        | sed -E 's/^[[:space:]]+//')"

  case "$s" in
    terraform*|tofu*)
      printf '%s' "$s" | grep -qiE '^(terraform|tofu)([[:space:]].*)?[[:space:]](apply|destroy|import|taint|untaint|force-unlock)([[:space:]]|$)' \
        && block "terraform/tofu state mutation ($s)"
      printf '%s' "$s" | grep -qiE '^(terraform|tofu)[[:space:]]+state[[:space:]]+(rm|mv|push|replace-provider)([[:space:]]|$)' \
        && block "terraform/tofu state surgery ($s)"
      ;;
    packer*)
      printf '%s' "$s" | grep -qiE '^packer([[:space:]].*)?[[:space:]]build([[:space:]]|$)' \
        && block "packer build ($s)"
      ;;
    aws*)
      # Match the operation in its real position (`aws [global flags] <service> <op>`),
      # not anywhere in the line: the old pattern allowed the verb to appear inside a
      # --filters or --query VALUE, e.g.
      #   aws ec2 describe-instances --filters Name=tag:Name,Values=create-foo
      # which is read-only but used to match `create-[a-z-]+`.
      # --flag=value and "--flag value" are ALTERNATIVES: written as separate optional
      # groups, the space-value branch also swallowed the service name after a
      # --flag=value, so `aws --region=us-east-1 ec2 delete-volume` escaped the guard.
      a="$(printf '%s' "$s" | sed -E 's/^aws(([[:space:]]+--[a-z][a-z0-9-]*(=[^[:space:]]*|[[:space:]]+[^-][^[:space:]]*)?)*)[[:space:]]+/aws /')"
      printf '%s' "$a" | grep -qiE '^aws[[:space:]]+[a-z0-9-]+[[:space:]]+(run-instances|terminate-instances|start-instances|stop-instances|create-[a-z-]+|delete-[a-z-]+|modify-[a-z-]+|put-[a-z-]+|attach-[a-z-]+|detach-[a-z-]+|authorize-[a-z-]+|revoke-[a-z-]+)([[:space:]]|$)' \
        && block "aws mutating call ($s)"
      ;;
  esac
done <<< "$segments"

exit 0
