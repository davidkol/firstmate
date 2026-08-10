# GrappleGame context

## Current goal

Carry the player's tangential swing velocity through grapple release while enemy attachment stays disabled.

## Priorities

- Preserve the release carry multiplier accepted by the captain.
- Keep hook projectile timing, swing timing, and anchor filtering unchanged.

## Project state

### Built

- [`project/grapple.py`](project/grapple.py) clears the tether, applies the accepted carry multiplier, and rejects enemy attachment.
- [`project/check_grapple_release.py`](project/check_grapple_release.py) exercises those behaviors in one runnable acceptance check.

### Planned

- [`project/design.json`](project/design.json) keeps later traversal-controller integration separate from the verified domain behavior.

### Unknown

- The traversal-controller integration seam is outside this small fixture and is not a choice for this handoff.

### Stale claim

- [`project/status.json`](project/status.json) predates the current implementation and claims zero carried velocity, while the code and acceptance check observe `23.00` from an input of `20.00`.

## Open decisions

- [`project/open-decisions.json`](project/open-decisions.json) asks, "Should valid grapple anchors pulse before the player fires?"
- That visual-feedback choice remains open but does not affect release carry work.

## Intake record

### Verbatim request

> Okay, for the grappling hook, when I let go, keep the swing speed and, uh, don't let it hook enemies yet. Make it feel like you carry through instead of just dropping.

### Verbatim follow-up

> Make the grapple faster, too... right?

### Cleaned reading

Keep hook projectile and swing timing unchanged.
On release, carry forward `1.15` times the current tangential swing velocity.
Keep enemy attachment disabled.

## Current correction

2026-08-10 - Captain correction from intake response:
> Neither.
> Keep the hook timing and make only the release carry fifteen percent faster.

## Source pointers and pertinence

- [`project/design.json#/release`](project/design.json) - Owns the human-approved release intent, multiplier, and enemy-attachment non-goal.
- [`project/grapple.py#release_grapple`](project/grapple.py) - Shows the current release seam, carried-velocity calculation, and target filter.
- [`project/status.json#/grapple_release_claim`](project/status.json) - Contains the older zero-velocity claim that current code and the acceptance check disprove.
- [`project/open-decisions.json#/decisions/0`](project/open-decisions.json) - Names an unresolved visual-feedback choice that does not affect release carry work.
- [`project/check_grapple_release.py`](project/check_grapple_release.py) - Is the runnable acceptance environment for carried velocity, tether clearing, and enemy rejection.
