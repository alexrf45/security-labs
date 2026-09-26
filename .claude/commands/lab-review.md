---
description: Periodic posture review of the range — cost, live footprint, all 11 safety invariants, doc and harness drift.
---

Produce a periodic **posture review** of the range and write it to
`_docs/reviews/cloud-range-review-<YYYY-MM-DD>.md`. This is the cloud successor to
the archived `home-0ps-review-*` series. Read-only survey; the output is a document.

Find the review you are superseding with `ls _docs/reviews/cloud-range-*review-*.md` —
the prefix is not stable across the series (the first one is
`cloud-range-implementation-review-2026-09-25.md`), so match loosely and take the newest
by date, not by name.

## Gather (all read-only)

1. **Repo state** — `git log --oneline -15`, `git status --short`, what changed
   since the last review in `_docs/reviews/`.
2. **Cost** — run `/cost`: projected (infracost) + actual (provider bill) vs the
   **$30/mo ceiling**. This is the headline metric.
3. **Live footprint** — run `/lab-status`: running instances, state-bearing roots,
   tailnet.
4. **Safety invariants — the load-bearing step.** This command is the *only* owner of
   the invariant audit (the `security-engineer` agent that half-claimed it was deleted
   2026-09-26 as off-topic). Walk **all eleven** invariants in
   [range-safety.md](../rules/range-safety.md) and record a verdict for each — a silent
   pass is not a pass; say which ones you could not check and why.

   Audit **both** layers, because they fail differently: the **code** (what the roots
   declare) and, when something is applied, the **live state** (what AWS actually has).
   Drift between them is itself a finding.

   | # | Invariant | Check in code | Check live (if applied) |
   |---|---|---|---|
   | 1 | No egress route on victim subnets | victim route tables in `range-network/routing.tf` carry no `0.0.0.0/0` to igw/nat/peering | `aws ec2 describe-route-tables` |
   | 2 | No public IP on any victim | `associate_public_ip_address = false` on every scenario host; `map_public_ip_on_launch = false` on victim subnets; no `aws_eip` outside ops | `aws ec2 describe-instances` — any victim with `PublicIpAddress` is a Blocker |
   | 3 | Tailscale-only entry, no public bastion | no SG ingress from `0.0.0.0/0` on any port | `aws ec2 describe-security-groups` |
   | 4 | Only hardened ops boxes bridge in | only the attacker/collector SGs reach victim SGs | — |
   | 5 | No control-plane reach from victims | `metadata_options` IMDSv2 `required` + `http_put_response_hop_limit = 1`, and **no** `iam_instance_profile` on any scenario host | `describe-instances` `MetadataOptions` |
   | 6 | Egress-deny by default | no blanket allow-all egress on victim SGs | — |
   | 7 | Telemetry one-way | victims → collector only; collector SG never initiates into a victim subnet | — |
   | 8 | No lab-admin data on scenario hosts | no secrets/SIEM index in scenario `user_data`; grep the scripts | — |
   | 9 | State split intact | three separate local states; downstream roots use tag-filtered **data sources**, never `terraform_remote_state` | — |
   | 10 | VPC DNS disabled | `enable_dns_support = false` **and** `enable_dns_hostnames = false` + DHCP option set with public resolvers | `aws ec2 describe-vpcs --vpc-ids <id> --attribute enableDnsSupport` (and `enableDnsHostnames`) |
   | 11 | SG + NACL ops↔victim separation | victim NACL egress limited to telemetry + ephemeral return, victim↔victim permitted; SG stateful rules intact. **Both are primary** — neither is belt-and-braces | `aws ec2 describe-network-acls` |

   `grep` is enough for most of the code column. Invariant 10 is the one that looks fine
   and isn't: AmazonProvidedDNS cannot be filtered by SG or NACL and is not logged, so if
   either DNS attribute is `true` that is a live exfil channel and a **Blocker**,
   regardless of what the route tables say.
5. **Doc/build drift** — do the runbooks match the tree? Any TODO/`❌ not applied`
   phases? Broken links?
6. **Harness health** —
   - `/lint` clean, and `_hack/scripts/guard-mutations.test.sh` green (the mutation guard
     is a safety control; an untested guard has silently failed open before).
   - Plugins still lean ([skills-and-plugins.md](../rules/skills-and-plugins.md))?
     Check **both** `.claude/settings.json` *and* `~/.claude/settings.json` — the rule
     only governs the project file, and drift has shown up user-globally. Report the
     actual enabled count, not the documented one.
   - Do `CLAUDE.md`'s command/agent/skill tables match what is on disk? (`ls
     .claude/commands .claude/agents .claude/skills`.) This table has drifted before.
   - Any rule contradicting another rule, or contradicting an accepted ADR? Two rules
     files are loaded into the same prompt, so a contradiction is an active hazard, not
     a tidiness issue.

## Write the review

House format, mirroring the archived reviews:

- Front-matter blockquote: date, trigger, scope.
- **Executive Summary** — where the range is, what changed, budget standing.
- **What changed since <last review>** — table.
- **Findings** — tiered/ID'd (e.g. `C-1` cost, `S-1` safety, `D-1` docs), each with
  severity, evidence, and a fix.
- **Cost standing** — projected + actual vs $30, trend.
- **Next steps.**

Supersede the prior review (note it at the top). Link the ADRs. Keep real values —
this is an internal review, not public-tier docs.
