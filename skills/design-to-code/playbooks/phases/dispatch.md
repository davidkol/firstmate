# Phase: DISPATCH

Send tasks to domain specialist agents. Two-pass model: RESEARCH first, then AUTHOR.

## When to Use

**Use DISPATCH when:**
- A specialist template exists in `.claude/specialists/` for the target system
- The task is primarily within one system's domain
- The system's spec is in the rehabbed format (How It Works + Known Traps)

**Fall back to BRIEF (phases/brief.md) when:**
- No specialist template exists for the target system
- The task spans multiple systems and can't be decomposed
- The spec hasn't been rehabbed yet

## Two-Pass Flow

```
Pass 1: RESEARCH — specialist finds the answers
  Orchestrator writes questions → Specialist reads code + spec → Returns findings

  Orchestrator (with user) reviews findings → Makes decisions

Pass 2: AUTHOR — specialist writes the brief
  Orchestrator sends resolved decisions → Specialist writes mechanical brief → Returns brief

  Orchestrator reviews brief → Saves to docs/briefs/
```

**Why two passes:** Combining research and authoring in one pass causes the specialist to shortcut analysis to get to the brief. Separating them forces actual code tracing before any decisions are made. The research output is reviewable — you see what the specialist found before any decisions are made from it.

## Pass 1: RESEARCH Dispatch

### Writing Good Questions

The orchestrator's value in RESEARCH is asking the RIGHT questions. Bad questions get surface answers. Good questions force the specialist to trace code paths and surface edge cases.

**Bad:** "How does the reactive handler work?"
**Good:** "What is the reactive handler's gate check? Show the exact code at the line. What are the toggled and instant handlers' gate checks? If they differ, describe each difference."

**Bad:** "What's the ICD pattern?"
**Good:** "After execution, how does each of the 3 trigger handlers set the ICD timer? Show exact code for all 3. What does `_get_effective_icd(0.0)` return — trace the function and compute the result."

**Bad:** "How should we fix this?"
**Good:** "What method ticks down `icd_timer`? Name, file, line number. What test infrastructure exists in the test file for reactive skills? List helper functions and what they create."

Rules for writing questions:
1. Ask about code state, not recommendations
2. Ask for exact file:line evidence
3. Ask "do patterns X and Y differ?" rather than "which pattern should we use?"
4. Ask about edge cases explicitly: "what happens when input is 0?" "what if this field is null?"
5. Ask about test infrastructure: "what helpers exist?" "what method ticks this timer?"
6. Reference spec traps: "TRAP-3 says X — verify this against current code"

### Assembling the RESEARCH Prompt

Read these files in order:
1. `.claude/specialists/_protocol.md` — shared protocol
2. `.claude/specialists/<system>.md` — system config (body only, skip frontmatter)
3. Each file listed in `spec:` and `refs:` frontmatter fields

Construct the prompt:
```
[_protocol.md content]

[specialist config body]

## System Specification
[contents of the spec file]

## Cross-Cutting References
[contents of each ref file, with headers]

## Mode
RESEARCH

## Questions
[numbered list of specific questions]
```

Dispatch as Agent. Do NOT use `isolation: "worktree"` — research is read-only.

### Reviewing Research Findings

When the specialist returns:
1. Check each answer has file:line evidence (not just claims)
2. Read the "Differences Found" section carefully — these are your decision points
3. Read "Edge Cases" — these often reveal issues the questions didn't anticipate
4. Present findings + decisions to the user if any are non-obvious

## Pass 2: AUTHOR Dispatch

After decisions are made (by you and the user, informed by research findings):

Construct the prompt:
```
[_protocol.md content]

[specialist config body]

## System Specification
[contents of the spec file]

## Cross-Cutting References
[contents of each ref file, with headers]

## Research Findings
[paste the specialist's research report — the specialist needs this context]

## Resolved Decisions
[numbered list — each decision cites the research finding that informed it]

## Mode
AUTHOR

## Task
[what to accomplish, which files, constraints]
```

Dispatch as Agent. Do NOT use `isolation: "worktree"` — the output is a brief document, not code.

### Reviewing the Brief

1. **Decisions followed:** Does each change match a resolved decision?
2. **OLD/NEW uniqueness:** For each OLD string, is it unique in its file?
3. **Guard logic:** If conditionals were added, trace both branches.
4. **Test correctness:** Do tests use the right methods (confirmed in research)?
5. **Scope:** No changes beyond what was decided.

Save approved brief to `docs/briefs/`.

## Pass 3: VERIFY (high-risk only)

After a worker executes the brief:

```
[same assembly as AUTHOR, plus:]

## Mode
VERIFIER

## Executed Brief
[the brief that was executed]

## Changes Made
[git diff summary or changed file list]
```

## Multi-System Tasks

If the task touches 2+ systems:
1. RESEARCH dispatch to each system's specialist (can be parallel)
2. Cross-check findings yourself (you hold the cross-system picture)
3. Make decisions informed by all specialists' findings
4. AUTHOR dispatch to each specialist for their system's changes

## Pipeline Summary

```
Full pipeline:
  Orchestrator → writes questions
    → Specialist RESEARCH (fresh code reading with domain knowledge)
      → Orchestrator + user review findings, make decisions
        → Specialist AUTHOR (writes brief from decided answers)
          → Worker executes in worktree
            → Specialist VERIFY (checks output)

Light pipeline (small/routine changes):
  Orchestrator → writes questions
    → Specialist RESEARCH
      → Orchestrator decides + Specialist AUTHOR (can combine if findings are clean)
        → Worker executes
```

## Sizing
- RESEARCH + AUTHOR = 2 specialist dispatches per task
- Max 3 tasks per orchestrator session (= up to 6 specialist dispatches)
- If more work remains, write a handoff

## Known Failure Modes

**FM-1: Specialist shortcuts analysis in one-shot mode.** When asked to research AND write a brief in one pass, the specialist skips deep code analysis to get to the brief. Fix: two-pass model (this doc).

**FM-2: Orchestrator asks vague questions.** "How does X work?" gets surface answers. "Show the exact gate check at line N, then show the equivalent in handlers Y and Z, then describe any differences" gets usable evidence.

**FM-3: Research findings taken on faith.** Specialist reports "method X does Y" but didn't trace it. Orchestrator should spot-check 1-2 claims by reading the cited file:line.
