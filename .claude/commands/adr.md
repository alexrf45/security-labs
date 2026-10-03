---
description: Scaffold the next ADR in the house format under _docs/decisions/.
argument-hint: [adr title]
---

Scaffold the next Architecture Decision Record in the house format.

## Steps

1. Find the next number: highest `NNNN` in `_docs/decisions/*.md` + 1 (zero-padded to 4).
2. Ask the user for the title if not given in `$ARGUMENTS`.
3. Write `_docs/decisions/NNNN-<kebab-title>.md` from the template below.
4. If this ADR supersedes another, set the old one's Status to
   `Superseded by ADR-NNNN` and cross-link both.
5. Do **not** commit — leave it for the user to review.

## Template

```markdown
# ADR-NNNN: <Title>

- **Status:** Proposed <YYYY-MM-DD>
- **Date:** <YYYY-MM-DD>
- **Deciders:** fr3d (with Claude review)
- **Related:** <links to related/superseded ADRs>

## Context

<The forces at play: the problem, constraints (recall the $30/mo ceiling, local
state, 1Password, Tailscale entry, Win+Linux, offense+defense), and why a decision
is needed now.>

## Decision

<The choice made, stated plainly. Tables for topology/segments/cost where useful.>

## Alternatives considered

- **<Option>** — <why considered, why rejected/deferred>.

## Consequences

- **Positive:** <...>
- **Negative / follow-ups:** <...>
```

Use today's date (`date +%Y-%m-%d`). Follow
[documentation.md](../rules/documentation.md).
