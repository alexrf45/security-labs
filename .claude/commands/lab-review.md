Produce a periodic **posture review** of the range and write it to
`_docs/reviews/cloud-range-review-<YYYY-MM-DD>.md`. This is the cloud successor to
the archived `home-0ps-review-*` series. Read-only survey; the output is a document.

## Gather (all read-only)

1. **Repo state** — `git log --oneline -15`, `git status --short`, what changed
   since the last review in `_docs/reviews/`.
2. **Cost** — run `/cost`: projected (infracost) + actual (provider bill) vs the
   **$30/mo ceiling**. This is the headline metric.
3. **Live footprint** — run `/lab-status`: running instances, state-bearing roots,
   tailnet.
4. **Safety invariants** — audit against [range-safety.md](../rules/range-safety.md):
   any public IP on a victim? any egress route on a detonation subnet? IMDSv2 +
   no-instance-role on detonation hosts? Tailscale-only entry? Flag violations.
5. **Doc/build drift** — do the runbooks match the tree? Any TODO/`❌ not applied`
   phases? Broken links?
6. **Harness health** — is the skills/plugins config still lean
   ([skills-and-plugins.md](../rules/skills-and-plugins.md))? `/lint` clean?

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
