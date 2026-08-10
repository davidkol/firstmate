# Companion intake manual acceptance

This manual scenario is the verification owner for the Companion intake causal chain.
The required chain is natural-language request -> project sources -> produced card and brief -> captain correction -> genuinely cold read.
Repository tests verify static routing contracts, authored artifact structure, byte-stable copying, brief-format compatibility, and the executable fixture behavior.
Those deterministic tests do not prove that Companion generated either artifact or that a cold Codex context understood the persisted result.

## Isolate the trial

1. Check out the commit under test in a fresh peer Firstmate code checkout and use an empty peer home.
2. Create a registered game project named `GrappleGame` containing only the files from `tests/fixtures/companion-intake/project/`.
3. Use a disposable code copy or sandbox boundary that makes `tests/fm-companion-intake.test.sh`, `tests/fixtures/companion-intake/cases.json`, and the authored `tests/fixtures/companion-intake/context-card.md` absent or unreadable to both Codex contexts.
4. Confirm that the peer home has no `data/project-context/GrappleGame.md` and no `data/<task-id>/brief.md` for this request.
5. Start a truly fresh Codex context with no transcript or summary from an earlier Companion trial.

## Verify the routing seam

Ensure that `Delivery` is registered as a game project with project-owned status sources before checking the routing seam.
Submit each routing request in a separate fresh context so an earlier selection cannot influence the next one.

1. Submit `Okay, we can try it for Delivery Pull up the status report of the game` with `Delivery` registered as a game project.
   Companion must own this request because the Delivery game itself is the requested report object.
2. Submit `/bearings for Delivery`.
   Bearings must own this explicit command even though it mentions Delivery.
3. Submit `give me the fleet work status for Delivery`.
   Bearings must own this request because fleet work is the requested status object.
4. Submit `Pull up the fleet status report`.
   Bearings must own this ordinary unnamed fleet request.

Capture the selected skill and response for all four requests.

## Exercise transformation and correction

1. Submit the following request in the fresh GrappleGame peer context.

   > Okay, for the grappling hook, when I let go, keep the swing speed and, uh, don't let it hook enemies yet. Make it feel like you carry through instead of just dropping.

2. Allow Companion to inspect only the project-owned design, implementation, status, open-decision, and acceptance files.
3. Capture the newly produced `data/project-context/GrappleGame.md` and `data/<task-id>/brief.md` before supplying any expected output.
4. Confirm that the produced artifacts preserve the request verbatim, give a meaning-faithful cleaned reading, identify the stale zero-velocity claim, retain the unrelated visual-feedback decision, and cite each pertinent source with a rationale.
5. Submit the following follow-up.

   > Make the grapple faster, too... right?

6. Confirm that Companion asks exactly one question about hook projectile speed versus swing acceleration and leaves release carry-through and enemy filtering unblocked.
7. Reply with the following correction, which rejects both offered options.

   > Neither. Keep the hook timing and make only the release carry fifteen percent faster.

8. Confirm that the produced card and brief keep both earlier messages verbatim, replace the interpretation with a `1.15` release carry multiplier, record the correction with its source, and expose no pertinent unresolved decision to the worker.
9. Run `tests/fixtures/companion-intake/project/check_grapple_release.py` from the code checkout.
10. Require the exact observation `grapple-release acceptance: velocity=23.00 tether_cleared=true enemy_attach=false`.
11. End the original Codex context completely.

## Prove the cold read

1. Start a genuinely cold Codex context with no prior chat, summary, expected case data, or authored context-card fixture.
2. Give it only the produced `data/project-context/GrappleGame.md` and the project sources cited by that card.
3. Ask it to state the current release behavior, explicit non-goals, relevant correction, stale-claim disposition, open decisions, seam invariants, and acceptance command.
4. Pass only if the response carries the corrected `1.15` release behavior, keeps hook and swing timing unchanged, keeps enemy attachment disabled, treats anchor visual feedback as an unrelated open decision, and names the runnable check.
5. Fail if the cold context needs the prior transcript, `cases.json`, the authored `context-card.md`, or an invented design choice.

## Evidence to retain

- Record the exact commit, fresh peer-home path, and isolated project path.
- Retain the four routing transcripts and selected-skill evidence.
- Retain the produced card and brief before and after correction.
- Retain the one-question and captain-correction transcript.
- Retain the exact acceptance command and output.
- Retain the genuinely cold context's input set and response.
- State explicitly that the authored expected fixtures were unavailable to both contexts.
