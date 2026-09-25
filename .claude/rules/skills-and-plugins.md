## Skills & Plugins — keeping context lean

The `agentic-awesome-skills` marketplace holds ~1,900 skills. Enabling the **monolith**
plugin injects every skill's name+description into **every** prompt (~1,900 entries) —
a large, permanent context tax. Skills only lazy-load their *body* on invoke; the
name+description list is always present while the plugin is enabled. So the lever for
"as needed" is **enabling narrow plugins, not lazy loading.**

### How this repo is configured (`.claude/settings.json`)

- The monolith `agentic-awesome-skills@agentic-awesome-skills` is set **`false`**
  (project override; it is also disabled globally in `~/.claude/settings.json`).
- Two **narrow bundle plugins** are enabled by default (~17 skills total):
  - `agentic-bundle-security-engineer` — offensive (cloud-pentest, linux-privesc,
    ethical-hacking, burp, vuln-scanner, top-web-vulns, security-auditor).
  - `agentic-bundle-aas-observability-ir` — defensive/IR (incident-responder,
    observability-engineer, grafana, distributed-tracing, postmortem, slo, …).
- A few high-value skills that **no small bundle contains** are **vendored** into
  `.claude/skills/` so they are always available and version-controlled:
  `active-directory-attacks`, `malware-analyst`, `threat-modeling-expert`,
  `aws-cost-operations`.

### Using more skills on demand (zero standing cost)

When a session needs a skill outside the enabled set (e.g. `metasploit-framework`,
`red-team-tactics`, `wireshark-analysis`, `memory-forensics`, `aws-security-audit`):

- Run `/plugin` and enable the relevant **bundle** (60 exist) or the monolith for that
  session, then disable it when done. This keeps the default context lean.
- Or, if a skill becomes a regular need for this repo, **vendor it** into
  `.claude/skills/` (copy from
  `~/.claude/plugins/marketplaces/agentic-awesome-skills/skills/<id>/`) and note it here.

### Rule

Do **not** re-enable the monolith by default or add broad bundles casually — each
enabled plugin is a standing context cost. Prefer vendoring a specific skill or a
per-session `/plugin` toggle.
