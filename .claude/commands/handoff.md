---
description: Compact this session into a session-handoff memory file so a fresh session can pick up.
argument-hint: [focus for the next session]
---

Compact the current conversation into a handoff document so a fresh session can pick up
cleanly. Modeled on the [h0me `handoff` skill](https://github.com/alexrf45/h0me/blob/main/.claude/skills/handoff/SKILL.md),
adapted to this repo: instead of a throwaway file in the OS temp dir, write the handoff
into this project's **persistent memory** so it is auto-recalled next session.

`$ARGUMENTS` (optional) = what the next session will focus on. If given, tailor the doc
to that focus; otherwise summarize the whole session's open threads.

## Steps

1. **Pick the focus.** From `$ARGUMENTS` (or, if empty, the most important unfinished
   thread). Slugify it, e.g. `phase1-deploy`, `siem-tuning`.
2. **Check for an existing handoff to update.** List the memory directory (the `memory/`
   path given in your environment) for a `session-handoff-*.md` that already covers this
   thread. **Update it** rather than creating an overlapping one (memory rule: one fact
   per file, no duplicates). Only create a new file for a genuinely new focus, and
   `[[cross-link]]` any related handoff.
3. **Write the handoff** to `<memory-dir>/session-handoff-<focus-slug>.md` using the
   template below (memory frontmatter, `type: project`).
4. **Update `MEMORY.md`** — refresh or add the one-line pointer for this handoff so the
   index reflects the new state.
5. **Do not commit.** Leave git to the user.

## Content rules

- **Don't duplicate artifacts.** ADRs, runbooks, READMEs, `variables.tf`, commits, diffs
  already say what they say — reference them **by repo path** and summarize only the
  delta / current state. A good handoff is a pointer map + "where we are + do this next",
  not a re-explanation.
- **Redact secrets.** Never write key/password/token values. Reference 1Password items by
  name and `op://` path only (`.claude/rules/secrets.md`). Never paste `*.tfstate`
  contents. Note if work is uncommitted (it usually is — the user commits, SSH-signed).
- **Absolute dates.** Convert "today"/"next week" to `YYYY-MM-DD`.
- **State faithfully.** What is done vs validated vs untested; what is applied vs only
  `validate`-clean. Don't imply deployment that hasn't happened.
- **Suggested skills / commands.** List the skills and slash commands the next session
  should reach for (e.g. `/lab-status`, `/cost`, `/lint`, the `active-directory-attacks`
  skill), so it starts oriented.

## Handoff template

```markdown
---
name: session-handoff-<focus-slug>
description: "<one line: current state + what the next session should do>"
metadata:
  type: project
---

**<YYYY-MM-DD> — <one-line status/where-we-are>.** Note anything uncommitted.

**Done this session** (reference by path, don't duplicate):
- <bullet — what changed, path, done vs validated vs untested>

**Next session — focus: <focus>.** First concrete actions:
1. <the very next command/step, pointing at the authoritative doc>

**Blockers / watch-outs:**
- <gotchas, fragile bits to validate, decisions still open>

**Key artifacts (paths):**
- <runbook / reference / ADR / root READMEs — where the detail actually lives>

**Suggested skills / commands:** <e.g. /lab-status, /cost, /lint, skill names>

<cross-links: [[session-handoff-...]]>
```

Keep it scannable — bullets over prose, paths over paragraphs.
