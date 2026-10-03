---
paths:
  - "_docs/**/*.md"
  - "**/README.md"
  - "CLAUDE.md"
---
# Documentation

Documentation is a first-class deliverable for this repo. The intent is to **publish
this project and host a documentation site** in the future, so docs are written to
that standard from the start. All documentation is **Markdown**.

## Structure — Diátaxis

Organize docs by the four Diátaxis modes so the future site maps cleanly:

- **Tutorials** — learning-oriented, start-to-finish ("stand up your first scenario").
- **How-to guides** — task-oriented runbooks ("build the attacker box", "roll back a
  scenario"). This is where operational runbooks live.
- **Reference** — information-oriented: module inputs/outputs, network tables,
  variable references. Auto-generatable where possible.
- **Explanation** — understanding-oriented: ADRs, design rationale, threat model.

`_docs/` holds `decisions/` (ADRs), `runbooks/` (how-to), `reference/`, and
`explanation/` as the range grows. `_docs/README.md` is the start-here index.

## Conventions

- **Markdown only.** No proprietary formats.
- Every Terraform **module and scenario root** ships a `README.md` documenting
  purpose, inputs, outputs, and an example.
- Use **Mermaid** for diagrams (renders on GitHub and most static-site generators);
  keep the source in the Markdown, not as opaque images.
- **ADRs** are numbered `NNNN-title.md` in `_docs/decisions/`, in the house format
  (Status / Date / Deciders / Related / Context / Decision / Alternatives /
  Consequences). Use `/adr` to scaffold the next one. When a decision supersedes
  another, mark the old one `Superseded by ADR-NNNN` and link both ways.
- Keep tables for anything tabular (network segments, cost, VLAN/subnet maps).
- Write for a public reader eventually: no unexplained internal jargon; expand an
  acronym on first use; keep real secrets and internal IPs out of public-tier docs
  (internal runbooks may use real values but say so at the top).

## YAML in docs/config

- 2-space indentation; document-start `---` optional; multiple docs per file allowed.
- Cloud-init / user-data YAML is linted by the `PostToolUse` yamllint hook on save.

## Site

The future documentation site is a **build step over this Markdown** (generator TBD —
the dead `lotusdocs`/Hugo and MkDocs attempts were removed). Structure the Markdown so
adopting a generator is configuration, not a rewrite.
