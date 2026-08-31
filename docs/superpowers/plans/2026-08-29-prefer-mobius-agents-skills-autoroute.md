# Prefer Mobius-generated .agents skills in auto-route

## Root cause

`findAgentSkills` already recurses into `.agents/skills/auto/<name>/SKILL.md`.
Auto-route then scores every skill the same way. Bundled / Claude local skills
(`frontend-design`, `qa`, `verification-before-completion`) get INTENT_HINTS
(+6) and domain deltas (+8–10). Mobius self-evolving skills live under
`.agents/skills/auto/` with project-specific names, so they lose the top-3
(`MAX_FULL_SKILLS = 3`, threshold 4). The warm-cache path has the same ranker.

## Goal

Workspace/global Mobius skills under `.agents` outrank ordinary local skills
(`.claude/skills`, `.github/skills`, `~/.copilot/skills`) when they have any
lexical or embedding overlap, and usually occupy at least one Auto-routed slot.

## Non-goals

- Changing skill discovery folders
- Game-mode CCGS/GF3A boosts (keep those higher)
- Commit unless the user asks

## Tasks

1. [x] Detect `.agents/skills/auto/` (generated) vs other `.agents/skills/`.
2. [x] Lexical prior + fused-score boost (gated on some relevance).
3. [x] Reserve one of the three auto-route slots for the best `.agents` skill.
4. [x] Apply on warm-cache, full load, and `simulateLexicalSkillRouting`.
5. [x] Unit tests in continue test/browser.

## Acceptance criteria

- Auto-generated skill with modest overlap appears in routed names alongside
  generic Claude skills.
- Unrelated auto skill with zero overlap is not forced in.
- `frontend-design` still routes for a pure UI brief when no `.agents` skill matches.
