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
# only if it *starts with* a guarded binary AND names a mutating subcommand. This
# avoids false positives when a command merely mentions "terraform apply" inside a
# heredoc, grep pattern, or string — authoring docs is never blocked.
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

# Split into segments on shell separators, evaluate each independently.
segments="$(printf '%s' "$cmd" | tr '\n;|&' '\n\n\n\n')"

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
      printf '%s' "$s" | grep -qiE '^aws[[:space:]].*[[:space:]](run-instances|terminate-instances|start-instances|stop-instances|create-[a-z-]+|delete-[a-z-]+|modify-[a-z-]+|put-[a-z-]+|attach-[a-z-]+|detach-[a-z-]+|authorize-[a-z-]+|revoke-[a-z-]+)([[:space:]]|$)' \
        && block "aws mutating call ($s)"
      ;;
    hcloud*)
      printf '%s' "$s" | grep -qiE '^hcloud[[:space:]].*[[:space:]](create|delete|rebuild|poweron|poweroff|reset|enable-[a-z-]+|disable-[a-z-]+|attach|detach|add-[a-z-]+|remove-[a-z-]+)([[:space:]]|$)' \
        && block "hcloud mutating call ($s)"
      ;;
    az*|gcloud*)
      printf '%s' "$s" | grep -qiE '^(az|gcloud)[[:space:]].*[[:space:]](create|delete|deploy|destroy|start|stop|update|add|remove)([[:space:]]|$)' \
        && block "az/gcloud mutating call ($s)"
      ;;
  esac
done <<< "$segments"

exit 0
