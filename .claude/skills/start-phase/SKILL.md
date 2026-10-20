---
name: start-phase
description: Start phase N of PHASES.md (the ScotchOS feature plan) - checks that the previous phase is approved, then does this phase's tasks, checks, docs and commit. Use when the user types /start-phase N.
argument-hint: <phase number>
disable-model-invocation: true
---

# Start phase $ARGUMENTS of PHASES.md

Keep context small: read only what these steps name.

1. **Read the plan, not all of it.**
   - `sed -n '/^## Rules for every phase/,/^---/p' PHASES.md` (the rules and the phase table).
   - `grep -n '^## Phase\|^\*\*Status:\*\*' PHASES.md` (every phase's status).
   - `sed -n '/^## Phase $ARGUMENTS:/,/^---/p' PHASES.md` (this phase). If there's no such phase, say so and stop.

2. **Gate.** Look at the status of the phase before this one (phase 1 has none):
   - `approved …`: go on.
   - `done`: ask the user (AskUserQuestion) whether they approve it, with the previous phase's "Done when" as what they should have tried. Yes → set its status to `approved <today>` and commit that line alone ("PHASES.md: approve phase N-1"). No → ask what's wrong, note it in that phase's Handoff and stop; fixing it happens in a chat for that phase, not this one.
   - `todo` or `in progress`: say that phase isn't finished and stop.
   - If **this** phase is already `done` or `approved`, say so and ask whether to redo or extend it before changing anything.

3. **Start.** Set this phase's status to `in progress`. Read the previous phase's Handoff lines, then the files under "Read first", and no others until a task needs them.

4. **Work** through the tasks in order. Tick each `- [ ]` as it's done. If a task turns out much bigger than the phase allows, or needs a decision the plan doesn't make, ask the user rather than guessing. Anything outside the repo: ask first (CLAUDE.md).

5. **Check:** the phase's "Done when", then `scotchos doctor`, `scotchos test`, `scotchos restart`, `scotchos log 2>&1 | grep -E 'WARN|ERROR'`. Use the check-shell skill when a widget's look matters. If a check can't be run here, say which one and why.

6. **Finish:** fill in the Handoff (≤ 5 lines: what the next phase must know, numbers measured, anything left undone). Set the status to `done`. Commit everything as "Phase N: <title>" with the attribution lines. Then tell the user briefly what changed, what to try before approving, and that `/start-phase <N+1>` will ask for their approval. If they approve in this chat, set `approved <today>` and commit that.
