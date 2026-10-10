# History

Bugs found by running it, all parse-clean. The lessons that still apply are rules in [CLAUDE.md](../CLAUDE.md) and [design.md](design.md).

## `may_block` defaulted to `may_capture`

That excluded the one player the pair exists for. The invulnerable player may not *capture* and must still *stop* a capture. Chaining the fallback to `may_capture` made the invulnerable player the one player the distinction did not apply to. Nothing errored: "the point kept capturing" is a legitimate thing for a point to do.

## A contested capture started and broke every tick

The reference implementation does this too: it starts a capture whenever a team is in the zone and breaks it on the next think if another team is as well. At 64 Hz that is 128 signals a second, a kill feed full of nothing, and `block_style 0` being *unobservable*, because the capture is always either just-started or just-broken. This addon refuses to start a contested capture at all. It is the rarer shape in this family's notes: not a value nobody consumes, but a value produced far too often.

## `capture_recovery_ticks` was a setting nothing set

The rule was exported, documented, range-limited, and read in exactly one place: a gate in `_maybe_start` testing a `_recovery_until` that was only ever assigned zero. `_break` had `if _recovery_until == 0: _recovery_until = 0`, a self-assignment that looks from three feet away exactly like the line that should have been there.

Nothing errored, which is why it survived: **restarting immediately is what the reference does**, so a mode that set the field to five seconds and got a capture back on the next tick was looking at correct-for-somebody-else behaviour. It is the family's most-repeated shape (an exported setting whose name occurs once in its repository), caught by the detector that shape has, and by a second one worth keeping: **an assignment whose left and right sides are the same name**. Both are in [game-dev/docs/detectors.md](../../../docs/detectors.md).

## The gate leaked every objective

Before the gate held a `weakref`, the set and its objectives formed a `RefCounted` cycle, and game-arena's dedicated server leaked every objective and definition at exit for as long as it had objectives ([design](design.md#the-gate-reaches-its-set-through-a-weak-reference)).
